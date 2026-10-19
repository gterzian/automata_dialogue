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
   reached stay background, so a short board grows from the top. `fit_twin`
   shares one horizon row between an upper branch growing up and a lower branch
   growing down: each branch pins its newest row to its outer edge, so the pair
   grows away from the horizon and mirrors exactly around it. Every grid cell is
   written each frame because nothing clears the grid between frames. Zoom
   changes `displayCols`/`displayRows` (and the drawable), so the same
   one-cell-per-cell mapping shows more or fewer board cells.
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
that edge at the boundary. A `pan(by:)` call aborts the follow for the rest of
the run (a `restart` restores it). E110 (left-growing, seed at the right edge)
leaves the viewport fixed and lets the growth fill it.

The reveal's camera is the only zoom. It lowers the zoom continuously so the
rows each branch has grown always fill its half: `RevealCamera.zoom` returns
`branchRows / (steps + 1)`, clamped to the floor. A zoom is a grid refit and a
redraw of the same target, not a drawable resize: the drawable is allocated
once at the floor's grid size, and the layer stretches the current grid over
it. At the floor each cell is one drawable pixel; earlier each cell covers
more than one, matching the compositor stretch the small grid used to get. The
floor comes from `DisplayLimits`: the widest grid the surface shows with one
cell per element, bounded by `ViewportGeometry.maximumGridCells`. A Retina
display reports its pixels (0.25× for a 1440 × 800 pt window); an LED surface
reports its addressable elements instead. The history ring and color buffer are
sized once for the floor. The layer's span buffer grows geometrically when the
continuously growing grid outgrows it, so a run reallocates it a handful of
times; a `LayerSink` is created per presented automaton, so the peak is
released on the next Return. Once the floor is reached the camera holds while
the branches keep growing, and older rows leave through the horizon. The CLI
exposes no manual zoom, pan, speed, or restart controls: the reveal is one
fixed animation.

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
window rests on the horizon line if the model is still working. The opening
sphere and whiteout take the first five seconds; the screen then goes black,
that field implodes to a dot, the dot explodes into the horizon line, and the
line then thins to a hairline before the automata start.

`CollapseVariation.seeded` turns one 64-bit draw into the run's look — phase
skew, form offset, contour wander, colour warmth, noise slice, and grain seed —
and `WorkingIndicator.start()` draws a fresh one for every run. New variation
belongs there, not in the shader as a new constant: everything visible has to
differ between runs, or the exchange reads as a fixed video.

One full-resolution render pass (`collapse_fragment`) composites the whole
sequence in draw order:

1. A mottled field, darkest at the corners, rose-to-violet by the run's warmth.
2. The opening shaded sphere, the soft glow inside it, and the white core that
   expands into the whiteout.
3. The screen goes black, that black field implodes to a dot, the dot explodes
   into a straight horizontal line, and the line thins to a hairline.

The scene is drawn to look painted rather than computed: one noise-driven
wander displaces every circle's radius, each disc's edge feathers over a
fraction of its own radius, shaded fills carry an off-centre highlight and the
field's texture, and a per-frame grain covers the frame. Discs whose edges only
differ by `fwidth` read as vector shapes, so keep the proportional feather when
adding one.

The ending page is the automaton's own palette background, with the grain
flattened away, so the handoff does not shift colour. The ending line is exactly
one automaton row thick: the window passes half the twin grid's row height to
the indicator, so the first reveal frame replaces the line without a pop. `WorkingIndicator.isSettled` becomes true after that final
line has been presented, and the window polls it before configuring the
automaton, so a fast model never cuts off the ending.

The CPU recomputes the disc list and the timeline uniforms each frame. The
scene shader writes the drawable directly; there are no offscreen targets,
upscale, or bloom passes. The renderer waits for the GPU before rewriting the
shared uniform and disc buffers.

## What exists

- **Metal 4 compute** (`GPUContext`, `MetalSimulation`) — `MTL4CommandQueue`,
  `MTL4CommandAllocator`, reusable command buffers, a residency set, and the
  `seed_row`/`step_*`/`bump_head`/`fit`/`fit_twin` kernels. `MetalSimulation`
  owns the history ring and the GPU-side `head` counter and advances one chunk
  per `renderGPU(chunk:)`. A twin run maps that one history into two mirrored
  branches around a shared horizon row. `reseed(seed:)` regenerates the seed on
  the GPU (used by `RenderActor.restart`) without reallocating buffers.
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
  `CollapseTimeline`, `CollapseVariation`, `WorkingIndicator`,
  `IndicatorActor`) — the opening sphere and whiteout, then the ink dot that
  stretches into the horizon line the review window shows while the model runs.
  `IndicatorActor` owns the `GPUContext`, renderer, and `DisplayLinkClock` on
  its own `RenderExecutor`, the way `RenderActor` does for a run, and reuses the
  indicator and layer across runs so the pipeline compiles once.
- **Viewport geometry** (`ViewportGeometry`, `DisplayLimits`) — the cell size,
  `cols`/`rows` for a window, the ten-window board width, the centred or
  right-pinned start origin, the twin grid's shared horizon row, and the zoom
  floor the display can show.
- **Reveal camera** (`RevealCamera`) — the continuous pull-back: the zoom that
  keeps the rows a branch has grown filling its half, held at the floor once
  the region starts clipping older rows.

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
  `drawableSize` are set before the render thread starts; the render thread
  only acquires and presents drawables.

## Remaining work

- **The reveal's floor was measured at 0.25× on one machine.** A full frame at
  the floor grid (2880 × 1600 from a 720 × 400 base: one step, `fit` over
  4.6 M cells, span compaction, draw, GPU wait) takes 2.7 ms, and a pre-fitted
  grid draws in 1.6 ms. The drawable is allocated at the floor size from the
  first frame, so the clear and draw cost is the floor cost even at 1×; only
  the grid's fit and compaction are smaller earlier. The span buffer's worst
  case is 16 B per cell (~74 MB). Re-measure on the target display; if 60 Hz
  does not hold there, lower `ViewportGeometry.maximumGridCells` or raise the
  floor rather than guessing.
- **The collapse intro has a fixed timeline.** It does not track the model's
  actual progress; Metal exposes no per-frame utilization figure. The
  ten-second build carries the wait on its own, then holds its final horizon
  line.
- **The on-screen pipeline serializes every frame.** `MetalSimulation.commit`,
  `LayerSink`'s layer commit, and `CollapseRenderer.render` all wait for the
  GPU, because their buffers are shared across frames and the frame slots only
  rotate the command allocators. A deeper pipeline would need a per-slot copy of
  each shared buffer and texture.

## Testing

When `MTLCreateSystemDefaultDevice()` reports `.metal4`, `MetalTests` checks the
`seed_row` kernel against every `BoardStart` shape, that a run grows from the
seed, that a followed pattern scrolls the window at the boundary, that zoom
resizes the grid without restarting the run, and that the twin layout grows
both branches away from the horizon, mirrors them cell for cell, and refits both
on a zoom. `RenderActorTests` asserts the actor runs off the main thread,
delivers GPU-resident frames, advances on a clock tick, restarts, refits on
zoom, and exposes the twin run's step count. `RevealCameraTests` pins the
pull-back: it starts at 1×, never zooms in, matches the branches' growth one
for one, never hides the newest row above the floor, and holds the floor.
`RenderTests` pins the pan anchor (`leadColumn`) to each start shape, the
display floor, and the twin grid's rows. `LayerTests` reads the rendered
texture back to check spans are filled with palette colours, that a renderer
handles a grid resize, and that the sink serializes frames sharing buffers.
`CollapseTests` checks the timeline's phase boundaries and that every phase
reaches the renderer. The display-link presentation itself needs a screen and
is not tested here; the intro's look is reviewed by hand.
