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

## Submission beat

`SubmissionTimeline` drives the two-second beat between Return and the intro:
the input doubles into two full copies that part vertically, leaving the page
between them, then the doubled screen collapses for half a second onto the dot
the intro starts from. `SubmissionRenderer` samples a texture uploaded from the
input's `RasterImage`; `WorkingIndicator.playSubmission` swaps from the beat to
`CollapseTimeline` at `ReviewIntro.openingTime`, drawing both with the same
`CollapseVariation` so the dot's radius and colour match. The model runs
alongside both animations; `WorkingIndicator.start` plays the intro alone when
no raster is available. Both use the indicator's drawable and clock, so there is
no view swap between the beat and the intro.

## Collapse intro

`CollapseTimeline` drives the intro the review window shows while the model's
turn is prepared. The window starts the cycle at `ReviewIntro.openingTime`,
where the opening dot is fully drawn and no layer has begun to grow, and freezes
on its rest frame if the model outlasts it. `WorkingIndicator` freezes its
display link with it, so the window keeps the last presented frame and stops
drawing. The indicator runs at 30 fps on a reduced drawable so it shares the
GPU with inference (see the window sequence in `AGENTS.md`). Its appearance is
accepted by visual inspection; the timeline and the shader are the place to
change it.

`CollapseVariation.seeded` turns one 64-bit draw into the run's look, and
`WorkingIndicator.playSubmission` and `start` draw a fresh one for every run.
Position is deliberately not part of the variation: every layer is centred, so
the dot and the resting line never slide sideways. New variation belongs there,
not in the shader as a new constant: every run has to differ, or the exchange
reads as a fixed video.

The resting frame becomes the reveal's first frame for an entry whose seed row
is a single centred cell. `AutomatonWindow` plays one more beat for those
entries: `settle` retracts the line onto that cell, half a cell right of the
frame's centre because the viewport's centre column starts at the centre line,
and in the palette colour that cell holds. The retraction's last frame is the
rest frame with `settle` at 1, so the reveal starts from the dot the automaton
actually begins with. Every other entry keeps the line, which is already its
first row.

The CPU recomputes the timeline uniforms each frame. The scene shader writes the
drawable directly; there are no offscreen targets, upscale, or bloom passes. The
renderer waits for the GPU before rewriting the shared uniform buffer, so a
frame must finish before the next one is written.

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
- **Submission beat** (`ShaderSource.submission`, `SubmissionRenderer`,
  `SubmissionTimeline`, `WorkingIndicator.playSubmission`) — the two-clone part
  and the collapse into the intro's opening dot, on the indicator's drawable.
- **Collapse intro** (`ShaderSource.collapse`, `CollapseRenderer`,
  `CollapseTimeline`, `CollapseVariation`, `WorkingIndicator`,
  `IndicatorActor`) — the one-cycle intro that runs while the model's turn is
  prepared and rests on the horizon line the review window shows until the
  choice lands, plus the retraction that joins it to a single-cell seed.
  `IndicatorActor` owns the `GPUContext`, both renderers, and
  `DisplayLinkClock` on its own `RenderExecutor`, the way `RenderActor` does for
  a run, and reuses the indicator and layer across runs so the pipelines
  compile once.
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
- **The collapse intro has a fixed length.** It does not track the model's
  actual progress; Metal exposes no per-frame utilization figure. If inference
  outlasts the intro, the window holds the line until the choice lands. A
  longer intro covers more of that wait, but delays every exchange where the
  model finishes sooner.
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
`CollapseTests` checks the rest frame the reveal continues from, the opening
frame the submission beat lands on, the submission timeline's phases, the seed
retraction, that a seed reproduces one run, and that the cycle, the submission
beat, and the retraction reach their renderers. The display-link presentation
needs a screen and is not tested here; the animation's look is accepted by
visual inspection.
