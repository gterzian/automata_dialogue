# Core/Render

Turns a `ProgramSpec` into a `GPUColorGrid` (row-major; one palette index per
display cell, or one colour per cell once a cell covers several source cells)
that stays on the GPU, and draws it into whatever
surface the frame's **render target** offers. The whole run — seed, step, fit,
compaction, draw — is GPU-resident; the CPU only sets the run's parameters and
never moves cell data.

## Compute and render

Every path here is the same three stages, and the third is the only one that
knows where pixels go:

1. **Compute** produces a device-independent value: `MetalSimulation` renders a
   `GPUColorGrid` on the GPU, and `CollapseTimeline`/`SubmissionTimeline` produce
   the intro's and the beat's frame values. Neither reads or writes a target, a
   texture, or a pixel format.
2. **Encode** turns that value into draw calls against a surface texture:
   `CellGridRenderer` (palette-index cells), `ToneGridRenderer` (colour cells),
   `CollapseRenderer`, `SubmissionRenderer`. A renderer
   takes a `MTLTexture` and encodes; it never acquires, presents, or configures
   a surface.
3. **Target** owns everything else about the destination: the pixel format the
   pipelines compile against, the elements the surface resolves one-to-one
   (`DisplayLimits`), when frames are due, the surface itself, and presenting it
   (`RenderTarget`). `MetalLayerTarget` is one implementation; a panel with a
   fixed element count is another, and no code above stage 3 changes.

A new destination is a new `RenderTarget` and nothing else: no branch on the
target's type above the seam, and no code between a value and the encode that
reads it back to the CPU. When a target needs a different mapping (a panel whose
elements are not a grid, say), that mapping is a kernel or a draw the target
runs, so the compute stage stays on the GPU.

`FrameSubmitter` is the one place that commits: frame slots, the residency set,
the completion handler, and the wait. A renderer only encodes into the command
buffer it hands over.

## Pipeline

One frame is a batch of dispatches plus a render pass, with explicit barriers.

1. **Seed** (`seed_row`, once per run or restart): writes the board's
   `BoardStart` into history row 0. One kernel covers all six start shapes
   (center cell, rightmost cell, random row, random 2-cell blocks, repeated
   block, base-`colors` number), so no CPU program stores a seed row. The
   SplitMix64 draw is indexed by cell, not carried across threads.
2. **Advance the board** (`step_eca`/`step_totalistic`/`step_k2r2` plus
   `bump_head`): each step reads the row at a GPU-side `head` counter and writes
   the next row into a history ring that grows to hold every row the run has
   produced; `injection` overwrites the centre cell after each step.
3. **Clip to the window** (`fit`): each display cell covers the block of source
   cells between its own sample position and the next cell's, so the blocks tile
   the board. At a sampling stride of 1 a block is one cell and the cell takes
   its value; past the display floor a block covers more, and the cell takes the
   block's **average colour** — a vote would erase a sparse pattern and beat
   against the automaton's own lattice, so the cell keeps every state's share of
   the block instead of one winner. Rows the run has not reached and columns off
   the board count as background, so a short board grows from the top. `fit_twin`
   shares one horizon row between an upper branch growing up and a lower branch
   growing down: the seed row sits on the horizon and, as the history fills the
   branch, the newest row sits on its outer edge, so the pair grows away from
   the horizon and mirrors exactly around it. The horizon keeps the seed row
   exactly rather than averaging it, because it is both branches' mirror axis
   and the frame the intro hands over. Every grid cell is
   written each frame because nothing clears the grid between frames. Zoom
   changes `displayCols`/`displayRows` up to the display floor, where one cell
   is one element of the surface. Past the floor the grid stays there and the
   stride grows, so the fit reduces the whole history into the grid (see
   `ViewportGeometry.sourceStride`).
4. **Draw** (`CellGridRenderer`, `ToneGridRenderer`): above the floor `runs`
   compacts each same-colour non-background run into a `Span`, `encode_draw`
   writes the indirect draw arguments on the GPU, and the render pass clears to
   the background and draws one instanced quad per span, so draw cost follows the
   structure, not the grid area. A toned grid has no palette index to compact and
   a 1-bit stipple of its coverage would cost a span per ink cell, so it goes out
   as one textured quad that samples the cells.

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

The reveal's camera is the only zoom. It opens at `RevealCamera.startZoom` — a
close-up where one cell is eight base cells — and lowers the zoom continuously
so the rows each branch has grown then always fill its half: `RevealCamera.zoom`
returns `min(startZoom, branchRows / (steps + 1))`. The pull-back ends where the
sampling widens the window to the whole simulated board
(`ViewportGeometry.stepsThatSpanBoard`), so the fit never samples past the
board's edge. `RenderActor` stops stepping there and plays the ending on the
clock's own ticks: the frame's `RevealMask` closes from the whole picture onto
the horizon row and then onto its centre point, and both draw paths draw the
page where the mask hides a cell, so the picture is eaten in place rather than
rescaled (see `CLI/README.md`). The seed
frame is delivered at that same scale, so the hand-off from the intro does not
jump. A zoom is a grid refit and a
redraw of the same surface, not a surface resize: the surface is allocated
once at the floor's grid size, and the target stretches the current grid over
it. At the floor each cell is one surface element; earlier the grid is
smaller and each cell covers more than one, matching the compositor stretch
the small grid gets. The
floor comes from the target's `DisplayLimits`: the widest grid the surface
shows with one cell per element, bounded by `ViewportGeometry.maximumGridCells`.
A Retina display reports its pixels (0.25× for a 1440 × 800 pt window);
`DisplayLimits.elements(columns:)` reports a fixed-resolution surface's
elements instead. Beyond the floor the grid stays at
the floor size and the fit samples the history at `sourceStride` — one display
cell per `stride` source cells on each axis — so the seed row stays on the
horizon, the newest row on the outer edges, and no row is dropped as the whole
history shrinks into the window. Those cells are colours, so the grid is four
bytes per cell and sized once for the floor grid; earlier frames use the same
buffer as one palette index per cell (see `GPUColorGrid.content`). The history
ring grows with the run (see Remaining work). The renderer's span buffer grows
geometrically while the grid grows to the floor, so a run reallocates it a
handful of times; a `CellGridSink` is created per
presented automaton, so the peak is released on the next Return. The CLI
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
the input separates into a double exposure — two copies a fraction of the
image's height apart, so it reads as one image with a ghost — then the doubled
screen collapses for half a second onto the dot the intro starts from, bringing
the two copies back together as it shrinks them. `SubmissionRenderer` samples a
texture uploaded from the
input's `RasterImage`; `WorkingIndicator.playSubmission` swaps from the beat to
`CollapseTimeline` at `ReviewIntro.openingTime`, drawing both with the same
`CollapseVariation` so the dot's radius and colour match. The model runs
alongside both animations; `WorkingIndicator.start` plays the intro alone when
no raster is available. Both draw into the same target, so there is
no surface swap between the beat and the intro.

## Collapse intro

`CollapseTimeline` drives the intro the review window shows while the model's
turn is prepared. The window starts the cycle at `ReviewIntro.openingTime`,
where the opening dot is fully drawn and no layer has begun to grow, and freezes
on its rest frame if the model outlasts it. `WorkingIndicator` freezes its
target with it, so the surface keeps the last presented frame and nothing is
drawn. The window gives the indicator's target 30 fps and a reduced surface so
it shares the GPU with inference (see the window sequence in `AGENTS.md`). Its
appearance is accepted by visual inspection; the timeline and the shader are
the place to change it.

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
and in the palette colour that cell holds. The cell is measured on the grid the
reveal opens on (`RevealCamera.startZoom`), so the hand-off does not change its
size; the resting hairline and the opening dot are scaled from a base-grid row
instead, so a closer reveal does not thicken the line. The retraction's last
frame is the rest frame with `settle` at 1, so the reveal starts from the dot
the automaton actually begins with. Every other entry keeps the line, which is
already its first row.

The CPU recomputes the timeline uniforms each frame. The scene shader writes the
target's surface directly; there are no offscreen targets, upscale, or bloom
passes. The renderer waits for the GPU before rewriting the shared uniform
buffer, so a frame must finish before the next one is written.

## What exists

- **Metal 4 compute** (`GPUContext`, `MetalSimulation`) — `MTL4CommandQueue`,
  `MTL4CommandAllocator`, reusable command buffers, a residency set, and the
  `seed_row`/`step_*`/`bump_head`/`fit`/`fit_twin` kernels. `MetalSimulation`
  owns the history ring and the GPU-side `head` counter and advances one chunk
  per `renderGPU(chunk:)`; the ring grows geometrically when the run outlives it
  so the fit can keep sampling back to the seed. A twin run maps that one
  history into two mirrored
  branches around a shared horizon row. `reseed(seed:)` regenerates the seed on
  the GPU (used by `RenderActor.restart`) without reallocating buffers.
- **Render seam** (`RenderActor`, `RenderExecutor`, `FrameSink`, `FrameClock`)
  — `RenderActor` confines the Metal objects to a dedicated run-loop thread and
  delivers GPU-resident `RenderFrame`s to a `FrameSink`. A `FrameSink` may read
  the frame's buffer only on the render actor. `RenderPacing` turns clock ticks
  into advances: `.fixed` for deterministic tests, `.timed` accumulates
  `Δ × stepsPerSecond` and clamps each tick; `setPacing` changes a driven run's
  rate in flight. `RenderActor.makeCellGridSink(target:)` builds the sink on the
  actor's own `GPUContext`, so the sink and the simulation share one device,
  queue, and residency set.
- **Render target** (`RenderTarget`, `RenderSurface`, `MetalLayerTarget`,
  `DisplayLinkClock`) — the swap point between the render logic and the surface
  it draws into. A target owns the pixel format the pipelines compile against,
  the elements it resolves one-to-one (`DisplayLimits`, which the zoom floor is
  computed from), the frame loop, the surface the frame draws into, and
  presenting it. `MetalLayerTarget` is the on-screen implementation: its frame
  loop is a `CAMetalDisplayLink` (`preferredFrameLatency = 1`) whose update's
  drawable becomes the frame's surface, and presenting it shows the frame. The
  link delivers updates for a layer that is not in a window yet, so a presenter
  can draw before the window swaps the layer in; the sink and the indicator
  report when a presented frame has reached the layer (`hasPresentedFrame`,
  which needs two presents because the first lands at the next update) and the
  window waits for it, since a swap onto a layer with nothing presented shows
  nothing. A
  surface backed by something other than a layer implements the same protocol
  and nothing above it changes.
- **Cell-grid sink** (`CellGridSink`, `CellGridRenderer`, `ToneGridRenderer`) —
  the sink draws each delivered `GPUColorGrid` into the target's surface; a grid
  of palette indices is compacted into spans, a grid of colours is drawn as one
  textured quad. The window refits every display row each frame, so an index
  frame recompacts the whole grid. Both paths take the frame's `RevealMask` and
  draw the page where it hides a cell.
- **Reveal ending** (`RevealEnding`, `RevealMask`, `RevealTimeline`,
  `RevealVariation`, `RenderActor.advanceEnding`) — the wipe that eats the
  stopped picture back onto the horizon row and closes the line into its point,
  with a seeded wander on its edges so no two runs eat the picture alike.
- **Submission beat** (`ShaderSource.submission`, `SubmissionRenderer`,
  `SubmissionTimeline`, `WorkingIndicator.playSubmission`) — the two-clone part
  and the collapse into the intro's opening dot, on the indicator's target.
- **Collapse intro** (`ShaderSource.collapse`, `CollapseRenderer`,
  `CollapseTimeline`, `CollapseVariation`, `WorkingIndicator`,
  `IndicatorActor`) — the one-cycle intro that runs while the model's turn is
  prepared and rests on the horizon line the review window shows until the
  choice lands, plus the retraction that joins it to a single-cell seed.
  `IndicatorActor` owns the `GPUContext` on its own `RenderExecutor`, the way
  `RenderActor` does for a run, and reuses the indicator and its target across
  runs so the pipelines compile once.
- **Viewport geometry** (`ViewportGeometry`, `DisplayLimits`) — the cell size,
  `cols`/`rows` for a window, the ten-window board width, the centred or
  right-pinned start origin, the twin grid's shared horizon row, the zoom
  floor the display can show, the sampling stride past it, and the cell budget
  that floor may allocate.
- **Reveal camera** (`RevealCamera`) — the close-up the reveal opens on and the
  continuous pull-back from it: the zoom that keeps the rows a branch has grown
  filling its half, never clamped; the fit's block average carries the zoom
  below the display floor.

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
  `residencySet` must be added to the queue as well, which
  `MetalLayerTarget.attach(to:)` does for its layer.
- **The `CAMetalLayer` is shared across actors.** `MetalLayerTarget` receives
  the main thread's view backing layer and uses it on the render
  thread, so `Core/Render` declares `CAMetalLayer` `@unchecked Sendable` to make
  that hand-off expressible. The layer's `pixelFormat`, `contentsScale`, and
  `drawableSize` are set before the render thread starts; the render thread
  only attaches the device, acquires drawables, and presents them.

## Remaining work

- **Keeping the whole history costs memory that grows with the run.** The
  history ring holds every source row, about `boardWidth` bytes per step (a
  ten-window board at the CLI's 40 rows/s is ~288 KB/s), and each growth copies
  the rows on the render thread. A window left on one automaton for minutes
  holds tens to hundreds of MB, and a growth copy after a long run can pause
  the reveal. A cap would have to hold the camera there and let the oldest rows
  leave as before.
- **The board bounds the reveal.** The pull-back ends once the window's
  sampling spans the ten-window board, so a longer reveal would need a wider
  board, which grows the history memory with it.
- **A toned grid's texture view requires a 16-byte row stride.**
  `MTLBuffer.makeTexture` asserts that `bytesPerRow` is a multiple of 16 rather
  than returning nil (verified: 4- and 8-byte rows trap, 16-byte rows work), so
  `ToneGridRenderer`'s view over a toned grid needs `cols % 4 == 0`. A
  screen-sized window usually gives that, but a window width whose floor grid
  is not a multiple of four columns traps. Rounding the floor's column count up
  to a multiple of four would fix it, at the cost of up to three background
  columns at the right edge.
- **The below-floor fit estimates a block's colour from nine samples.** A
  display cell averages the block of source cells it covers, read at up to three
  stratified positions per axis, so a block larger than 3 × 3 is estimated rather
  than counted: a feature smaller than its block is under-weighted, and its
  colour can vary a little between neighbouring cells that cover the same
  structure. A sparse pattern therefore fades as its cells start to cover more
  than one source cell — a block holding one ink cell among four reads as a
  quarter-tone — where an index cell of the same history is solid ink. The
  horizon row stays an exact sample, because the seed row is the
  axis the branches mirror around and the frame the intro hands over. Counting
  the whole block instead would need a summed-area table over the history. The
  blocks still re-round every frame as the stride moves, so a pattern below the
  floor re-lays out rather than blurring: it can crawl, but its rows and edges
  keep their place. A toned cell is one surface element, so no amount of
  averaging softens an edge below that element.
- **The reveal's floor was measured at 0.25× on one machine.** At a floor grid
  of 2880 × 1599 (a 1440 × 800 pt window on a 2× display), an index frame at a
  stride of 1 refits in 1.3 ms and draws in 0.7 ms, and a toned frame at a
  stride of 2 refits in 2.1–3.2 ms and draws in 0.6–0.9 ms: the tone path reads
  the same nine samples but has more cells inside the history to read, and its
  draw is one quad instead of a span list. The surface is allocated at the floor
  size from the first frame, so the draw cost is the floor cost even at 1×; only
  the grid's fit and compaction are smaller earlier. The span buffer is 16 B per
  cell, so the 8 M-cell cap is 128 MB at worst; the buffer is sized to the grid
  the run actually reaches. Re-measure on the target display; if 60 Hz does not
  hold there, lower `ViewportGeometry.maximumGridCells` or raise the floor rather
  than guessing.
- **The collapse intro has a fixed length.** It does not track the model's
  actual progress; Metal exposes no per-frame utilization figure. If inference
  outlasts the intro, the window holds the line until the choice lands. A
  longer intro covers more of that wait, but delays every exchange where the
  model finishes sooner.
- **The on-screen pipeline serializes every frame.** `FrameSubmitter.submit`
  waits for the GPU, because the simulation's and the renderers' buffers are
  shared across frames and the frame slots only
  rotate the command allocators. A deeper pipeline would need a per-slot copy of
  each shared buffer and texture.
- **The reveal and the intro own one `GPUContext` each.** `RenderActor` and
  `IndicatorActor` each create a context on their own render thread, so a single
  target that must serve both phases (a panel with one device buffer, say) has
  to be driven by one of them. Sharing one context would mean one render thread
  for both.

## Testing

When `MTLCreateSystemDefaultDevice()` reports `.metal4`, `MetalTests` checks the
`seed_row` kernel against every `BoardStart` shape, that a run grows from the
seed, that a followed pattern scrolls the window at the boundary, that zoom
resizes the grid without restarting the run, that a display cell below the
floor keeps the block's average colour instead of a vote, and that the twin
layout grows both branches away from the horizon, mirrors them cell for cell,
refits both on a zoom, and keeps the seed row on the horizon once the run
outgrows the display floor (including across a history-ring growth).
`RenderActorTests` asserts the actor runs off the main thread, delivers
GPU-resident frames, advances on each frame the target delivers, that
`stopDriving` ends them, restarts, refits on zoom, exposes the twin run's step
count, delivers the first frame of a reveal at the camera's close-up, ends the
pull-back once the sampled window spans the whole board, and plays the ending to
its settled point.
`RevealCameraTests` pins the camera: it opens at the close-up, holds it while
the branch has room, never zooms in, then matches the branches' growth one for
one and keeps pulling back below the display floor. `RenderTests` pins the pan
anchor (`leadColumn`) to each start shape, the display floor, the sampling
stride, the step count at which the window spans the board, and the twin grid's
rows. `CellGridTests`
reads the rendered
texture back to check spans are filled with palette colours, that a toned grid
is drawn through the tone renderer with its cells' own colours and its row
order, that a renderer handles a grid resize, that the sink draws into whatever
target it is given (with a target's own limits and pixel format), that a layer
target has no surface before its first display-link update, that a sink reports
its first presented frame, and that the sink
serializes frames sharing buffers.
`CollapseTests` checks the rest frame the reveal continues from, the opening
frame the submission beat lands on, the submission timeline's phases, the seed
retraction, that a seed reproduces one run, and that the cycle, the submission
beat, and the retraction reach their renderers, including that the intro draws
through an offscreen target rather than a layer and reports its first presented
frame. `RevealEndingTests` pins the other animation's workflow: the mask starts
on the untouched picture, eats it back to the horizon line, closes the line into
its centre point and rests there; the upper edge leads the lower one; a seed
reproduces one ending; and both draw paths draw the page where the mask hides a
cell. The display-link presentation
needs a screen and is not tested here; the animations' looks are accepted by
visual inspection.
