# Core/Render

Turns a `ProgramSpec` into a `GPUColorGrid` (one `UInt8` palette index per
display cell, row-major) that stays on the GPU, and draws it. The whole run —
seed, step, fit, span compaction, draw — is GPU-resident; the CPU only sets the
run's parameters and never moves cell data.

## Pipeline

One frame is a batch of dispatches plus a render pass, with explicit barriers.

1. **Seed** (`seed_row`, once per run or restart): writes the board's
   `BoardStart` into history row 0. One kernel covers all six start shapes
   (center cell, rightmost cell, random row, random 2-cell blocks, repeated
   block, base-`colors` number), so no CPU program stores a seed row. The
   SplitMix64 draw is indexed by cell, not carried across threads.
2. **Advance the board** (`step_eca`/`step_totalistic`/`step_k2r2` plus
   `bump_head`): each step reads the row at a GPU-side `head` counter and writes
   the next row into a ring of the newest `capacity` rows (sized for the widest
   zoom-out). `injection`
   overwrites the centre cell after each step.
3. **Clip to the window** (`fit`): display row `d` reads source step
   `step - (rows - 1) + d` at column `viewportOrigin + d`; rows the run has not
   reached stay background, so a short board grows from the top. Zoom changes
   `displayCols`/`displayRows` (and the drawable), so the same one-cell-per-cell
   mapping shows more or fewer board cells.
4. **Draw** (`LayerRenderer`): `runs` compacts each same-colour non-background
   run into a `Span`, `encode_draw` writes the indirect draw arguments on the
   GPU, and the render pass clears to the background and draws one instanced
   quad per span. Draw cost follows the structure, not the grid area.

Nothing crosses the CPU between the passes; the pass draws the compute output
directly. That is why the window simulates a **board much wider than the
display** (`ViewportGeometry.boardWidth`, ten windows) and renders only a
viewport: the pattern can leave the window and keep going, and the view pans to
follow it. `pan(by:)` slides the window. An entry whose pattern drifts sideways
declares `DisplayHints.follow` (signed columns per source step); the viewport
stays fixed while the leading edge is inside it, then scrolls just enough to keep
that edge at the boundary. A manual pan aborts the follow for the rest of the
run (a `restart` restores it). E110 (left-growing, seed at the right edge)
leaves the viewport fixed and lets the growth fill it.

Zoom is a real window resize, not a resample: `setZoom` scales the display grid,
its drawable, and the viewport together, so a zoomed-out view shows more board at
native resolution instead of skipping cells (which aliases a fractal into a
different-looking one). The history ring and color buffer are sized once for the
widest zoom-out, so a zoom reuses them; the layer's span buffer only grows when a
new maximum grid is reached.

The two barriers are different: a **dispatch→dispatch** barrier separates the
sequential step rows (row *n+1* reads the row *n* just wrote), and a
**dispatch→vertex** barrier publishes the spans and draw arguments before the
render pass reads them. The step rows cannot be one dispatch — for a board wider
than a threadgroup, tile halos would have to grow with the row count — so they
are a batch of dispatches. A full `MTLIndirectCommandBuffer` is unnecessary: the
command shape is constant and only the instance count varies, which the indirect
argument buffer already carries.

## Collapse intro

`CollapseTimeline` drives the intro the review window shows while the model
runs. It is a fixed ten-second timeline that freezes on its final frame, so the
window rests on the white page if the model is still working.

One full-resolution render pass (`collapse_fragment`) composites the whole
sequence in draw order:

1. A mottled mauve field, darkest at the corners.
2. Large discs from a nine-entry list, drawn back to front. Each disc is white,
   a shaded gradient, a ring, or a soft glow, with a dark rim and an optional
   penumbra.
3. Up to eight soft rays with their apexes at the center.
4. The late starburst, 48 alternating dark and light wedges.
5. The center discs and rings, which cover the rays where they converge.
6. The final blackout, the shrinking black field, and the ink point.

The CPU recomputes the disc/ray lists and the timeline uniforms each frame. The
scene shader writes the drawable directly; there are no offscreen targets,
upscale, or bloom passes. The renderer waits for the GPU before rewriting the
shared uniform, disc, and ray buffers.

## What exists

- **Metal 4 compute** (`GPUContext`, `MetalSimulation`) — `MTL4CommandQueue`,
  `MTL4CommandAllocator`, reusable command buffers, a residency set, and the
  `seed_row`/`step_*`/`bump_head`/`fit` kernels. `MetalSimulation` owns the
  history ring and the GPU-side `head` counter and advances one chunk per
  `renderGPU(chunk:)`. `reseed(seed:)` regenerates the seed on the GPU (used by
  `RenderActor.restart`) without reallocating buffers.
- **Render seam** (`RenderActor`, `RenderExecutor`, `FrameSink`, `FrameClock`)
  — `RenderActor` confines the Metal objects to a dedicated run-loop thread and
  delivers GPU-resident `RenderFrame`s to a `FrameSink`. A `FrameSink` may read
  the frame's buffer only on the render actor. `RenderPacing` turns clock ticks
  into advances: `.fixed` for deterministic tests, `.timed` accumulates
  `Δ × stepsPerSecond` and clamps each tick; `setPacing` changes a driven run's
  rate in flight. `RenderActor.makeLayerSink(layer:)` builds a layer sink on the
  actor's own `GPUContext`, so the sink and the simulation share one device,
  queue, and residency set.
- **On-screen sink** (`DisplayLinkClock`, `LayerSink`, `LayerRenderer`) —
  `DisplayLinkClock` conforms to `FrameClock` over `CAMetalDisplayLink`
  (`preferredFrameLatency = 1`); `LayerSink` owns the layer and the clock, and
  `LayerRenderer` turns a `GPUColorGrid` into a draw. The window refits every
  display row each frame, so every frame recompacts the whole grid.
- **Collapse intro** (`ShaderSource.collapse`, `CollapseRenderer`,
  `CollapseTimeline`, `WorkingIndicator`, `IndicatorActor`) — the discs, rays,
  starburst, and final shrink the review window shows while the model runs.
  `IndicatorActor` owns the `GPUContext`, renderer, and `DisplayLinkClock` on
  its own `RenderExecutor`, the way `RenderActor` does for a run, and reuses the
  indicator and layer across runs so the pipeline compiles once.
- **Viewport geometry** (`ViewportGeometry`) — the cell size, `cols`/`rows` for
  a window, the ten-window board width, the centred or right-pinned start
  origin, the zoom bounds and levels, and the grid those levels produce.

## Metal 4 gotchas

- **The argument table is live at GPU execution time.** Rebinding one table's
  addresses between encoded dispatches makes every dispatch resolve to the final
  address. The step kernels therefore read the current row from a GPU-side
  `head` counter that a 1-thread `bump_head` kernel advances, so all argument
  tables have constant bindings.
- **`CFRunLoopRun()` returns immediately when the run loop has no sources.**
  `RenderExecutor`'s render thread would exit before the first job arrived and
  every `await` on the actor would hang. `run()` adds an empty `CFRunLoopSource`
  to keep the loop alive.
- Swift names differ from the ObjC selectors: `device.makeMTL4CommandQueue()`;
  `device.makeCompiler(descriptor:)` and `device.makeResidencySet(descriptor:)`
  throw; `compiler.makeLibrary/makeComputePipelineState(descriptor:)`;
  `command.makeComputeCommandEncoder()`; `table.setAddress(_:index:)`;
  `encoder.dispatchThreads(threadsPerGrid:threadsPerThreadgroup:)`.
- Render names differ too: `command.makeRenderCommandEncoder(descriptor:)`;
  `compiler.makeRenderPipelineState(descriptor:)`;
  `render.setArgumentTable(_:stages:)`;
  `render.drawPrimitives(primitiveType:indirectBuffer:)`; the render pass colour
  attachment subscript is optional. The drawable arrives in the display-link
  update and is presented with `present()`; this SDK's `MTLDrawable` has no
  `waitForDrawable`/`signalDrawable`.
- **Compute-to-render ordering is explicit.** The compute encoder publishes the
  spans with `barrier(afterStages: .dispatch, beforeQueueStages: .vertex,
  visibilityOptions: .device)` before the render encoder reads them; the
  intra-encoder barriers only order dispatches within the compute pass.
- The residency set is Metal 4's only residency mechanism; buffers must be
  added and the set committed before use. A `CAMetalLayer`'s own
  `residencySet` must be added to the queue as well.
- **The `CAMetalLayer` is shared across actors.** `makeLayerSink(layer:)`
  receives the main thread's view backing layer and uses it on the render
  thread, so `Core/Render` declares `CAMetalLayer` `@unchecked Sendable` to make
  that hand-off expressible. The layer's `device`, `pixelFormat`, and
  `drawableSize` are set before the render thread starts; afterwards the render
  thread only acquires and presents drawables.

## Remaining work

- **The collapse intro has a fixed timeline.** It does not track the model's
  actual progress; Metal exposes no per-frame utilization figure. The ten-second
  build carries the wait on its own, then holds its final white page.
- **The on-screen pipeline serializes every frame.** `MetalSimulation.commit`,
  `LayerSink`'s layer commit, and `CollapseRenderer.render` all wait for the
  GPU, because their buffers are shared across frames and the frame slots only
  rotate the command allocators. A deeper pipeline would need a per-slot copy of
  each shared buffer and texture.

## Testing

When `MTLCreateSystemDefaultDevice()` reports `.metal4`, `MetalTests` checks the
`seed_row` kernel against every `BoardStart` shape, that a run grows from the
seed, that a followed pattern scrolls the window at the boundary, and that zoom
resizes the grid without restarting the run.
`RenderActorTests` asserts the actor runs off the main thread, delivers
GPU-resident frames, advances on a clock tick, restarts, and refits on zoom.
`RenderTests`
pins the pan anchor (`leadColumn`) to each start shape. `LayerTests` reads the
rendered texture back to check spans are filled with palette colours, that a
renderer handles a grid resize, and that the sink serializes frames sharing
buffers. `CollapseTests` checks the ten-second timeline freezes, that the discs
and rays draw, and that the ending goes mostly black and then shrinks to a bare
white page. The display-link presentation itself needs a screen and is not
tested here.
