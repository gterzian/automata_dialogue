# Core/Render

Turns a `ProgramSpec` into a `ColorGrid` (one `UInt8` palette index per display
cell, row-major) and, on the Metal path, into a GPU buffer. Three seams split
it: **simulation core**, **frame sink** (delivery), and **frame clock**
(pacing).

## Pipeline

The on-screen path is GPU-resident end to end: the CPU sets parameters and
never moves cell data. One frame is three passes —
1. **advance the board** (`MetalSimulation.advance`): a batch of `step_*`
   dispatches writes the chunk into the board's history buffer;
2. **clip to the viewport** (`fit`): the newest `rows` source rows × the
   `viewportOrigin` columns become `colorBuffer`, which *is* the visible cell
   grid;
3. **draw** (`LayerRenderer`): `runs`/`encode_draw` compact that grid into
   spans and a GPU-written indirect draw, and the render pass issues it.

Nothing crosses the CPU between the passes. A sink that asks for
`wantsGPUResidentFrames` gets a `GPUColorGrid` aliasing the simulation's
buffer, and the pass draws the compute output directly. That is why the review
window simulates a **board much wider than the window**
(`ViewportGeometry.boardWidth`) and renders only a viewport, instead of fitting
a whole board into a still frame: the pattern can leave the window and keep
going, and the view pans to follow it. The catalog board width is a property of
the entry, not of the display; the run's board is passed explicitly.

The two dependencies are different and are ordered explicitly: a
**dispatch→dispatch** barrier separates the sequential step rows (row *n+1*
reads the row *n* just wrote), and a **dispatch→vertex** barrier publishes the
spans and draw arguments before the render pass reads them. The step rows
cannot be one dispatch — for a board wider than a threadgroup, tile halos would
have to grow with the row count — so they are a batch of dispatches. A full
`MTLIndirectCommandBuffer` is unnecessary: the command shape is constant and
only the instance count varies, which the indirect argument buffer already
carries.

## What exists

- **CPU reference path** (`CPUAutomatonRenderer`, `IncrementalRenderer`) — runs
  the `Core/Programs` reference and fits the rows to a `ColorGrid` /
  `CGImage`. Always available; the correctness reference for the GPU path and
  the backend for the CLI's `render` command.
- **Metal 4 compute** (`GPUContext`, `MetalSimulation`, `MetalAutomaton`) —
  macOS 26 / Apple silicon. `MTL4CommandQueue`, `MTL4CommandAllocator`, one
  reusable `MTL4CommandBuffer`, a residency set, and the `step_*`/`bump_head`/
  `fit` kernels. `MetalSimulation` is the sink-independent core: it owns the
  history buffer and the GPU-side `head` counter and advances one chunk of
  source rows per `render(chunk:)`, so a caller animates instead of running the
  whole board in one commit. `MetalSimulation` also has a **scrolling** mode:
  it keeps only the newest `rows + 2` source rows in a ring and maps display
  row `d` to source step `step - (rows - 1) + d`, so a short board grows from
  the top and then the window follows the newest row without an end.
  `MetalAutomaton` is the one-shot wrapper.
- **Render seam** (`RenderExecutor`, `RenderActor`, `FrameSink`, `FrameClock`,
  `ReadbackSink`, `SinkFactory`) — `RenderActor` confines the Metal objects to
  a dedicated run-loop thread and delivers `RenderFrame`s to a `FrameSink`;
  `ReadbackSink` retains the latest frame for a CPU consumer. `RenderPacing`
  turns clock ticks into advances: `.fixed` for deterministic tests, `.timed`
  accumulates `Δ × stepsPerSecond` and clamps each tick; `setPacing` changes a
  driven run's rate in flight. `pan(by:)` slides the window and `restart()`
  reseeds without dropping the sink.
  `RenderActor.makeLayerSink(layer:)` builds a layer sink on the actor's own
  `GPUContext`, so the sink and the simulation share one device, queue, and
  residency set.
- **GPU-resident frames** — a sink that sets
  `wantsGPUResidentFrames` receives `GPUColorGrid` (the simulation's
  `colorBuffer` plus the rows this frame fitted) instead of a CPU `ColorGrid`,
  so the actor skips the readback. `LayerRenderer.render(gpu:)` appends the new
  rows to the spans it already compacted; display rows never change once
  fitted, so the accumulated spans stay valid. A frame with `firstRow == 0`
  starts a run and resets the counter. A **scrolling** frame moves the window
  every tick, so it reports `firstRow == 0` with every row and the sink
  recompacts the whole grid each frame.
- **On-screen sink** (`DisplayLinkClock`, `LayerSink`, `LayerRenderer`) —
  `DisplayLinkClock` conforms to `FrameClock` over `CAMetalDisplayLink`
  (`preferredFrameLatency = 1`); `LayerSink` is a `FrameSink` that owns the
  layer and the clock, and `LayerRenderer` turns a frame into a draw: a `runs`
  kernel compacts each same-colour non-background run into a `Span`, an
  `encode_draw` kernel writes the `MTLDrawPrimitivesIndirectArguments` on the
  GPU, and a render pass clears to the background and draws one instanced quad
  per span. `RenderActor.drive(clock:pacing:)` starts the clock on the render
  thread.
- **Working indicator** (`ShaderSource.indicator`, `IndicatorRenderer`,
  `WorkingIndicator`, `IndicatorActor`) — the beating ring animation the
  review window shows while the model runs: rings grow out to the edge and pull
  back in. One full-screen triangle; the
  fragment shader paints the rings from a `time` uniform, so no per-frame
  geometry is built on the CPU. `IndicatorActor` owns the `GPUContext`,
  renderer, and `DisplayLinkClock` on its own `RenderExecutor`, the way
  `RenderActor` does for a run, and reuses the indicator and layer across runs
  so the pipeline compiles once.
- **Fit** (`Fit`) — the one geometry rule both paths use.

Both paths converge on the same `ColorGrid`; the readback test compares them.

## Geometry and fit

`Fit` maps each display column to a block of source cells: nearest for
`k == 1`, majority vote for `k > 1`, the rightmost window for `pinRight`
(E110). A display column that reaches past the board reads background; it never
wraps to the left edge.

The animating review window sizes its grid with `ViewportGeometry` instead of
`Fit`: a cell edge of `minimumCellPoints` (2 points — the reference
visualizer's 4-pixel cell at the 2× scale a Retina display uses) sets `cols`,
and the run simulates a board `boardWindows` (10) windows wide so the pattern
keeps going after it leaves the first window and the view has room to pan. `ColumnMapping.window` maps one board cell per display column at a
movable `viewportOrigin` (kernel block 1), and `LayerRenderer` stretches the
small cell grid over the whole drawable. `IncrementalRenderer`/`MetalSimulation`
take the simulated board explicitly, so a narrow catalog entry still runs on a
wide board; `pan(by:)` slides the origin, clamped to `boardWidth - cols`, and
`RenderActor.pan(by:)` re-fits and delivers. An entry whose pattern drifts
sideways declares `DisplayHints.follow` (signed columns per source step). The
renderer leaves the viewport fixed while the pattern's leading edge is still
inside it, then scrolls the viewport just enough to keep that edge at the
boundary; a manual `pan(by:)` aborts the follow for the rest of the run (a
`reset` restores it). Scrolling from the start would push a growing pattern out
of view, so E110 (left-growing, seed at the right edge) leaves the viewport
fixed and lets the growth fill it. A run starts centred on the board
(rightmost for a rightmost or `pinRight` entry), grows from the top until the
window fills, then scrolls with the newest row at the bottom.
`ColumnMapping.fit` stays the still-image mapping for `CPUAutomatonRenderer`
and the CLI's `render` command.

Remaining work: majority vote erases sparse single-cell features when a board
is downsampled (E90's Sierpinski seeds at a reduced width). Under `.fit`,
boards narrower than the window use `k = 1`, so this only affects the 6101-wide
entries, which are dense. If a sparse entry ever needs downsampling, revisit
`Fit` and the Metal `fit` kernel together.

## Metal 4 gotchas

- **The argument table is live at GPU execution time.** Rebinding one table's
  addresses between encoded dispatches makes every dispatch resolve to the
  final address. The step kernels therefore read the current row from a
  GPU-side `head` counter that a 1-thread `bump_head` kernel advances, so all
  argument tables have constant bindings (the "one-thread kernel advances a
  GPU-side head counter" fallback).
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
  thread, so `Core/Render` declares `CAMetalLayer` `@unchecked Sendable` to
  make that hand-off expressible. The layer's `device`, `pixelFormat`, and
  `drawableSize` are set before the render thread starts; afterwards the render
  thread only acquires and presents drawables.

## Remaining work

- **The on-screen pipeline serializes every frame.** `MetalSimulation.commit`
  and `LayerSink`'s layer commit both wait for the GPU, because the simulation's
  color buffer and the renderer's span, counter, uniform, and palette buffers
  are shared across frames and the frame slots only rotate the command
  allocators. A 2-deep pipeline would need a per-slot copy of each shared
  buffer (and a fit window that cannot overlap the next advance); the readback
  path must keep its wait regardless.
- **`LEDSink`** behind the `RATER_SINK_LED` flag. Its geometry, colour order,
  and transport are open decisions, so it waits on hardware.

A sink that receives GPU-resident frames must read the buffer only on the
render actor and must treat `firstRow == 0` as a new run, because the spans
accumulate across frames.

## Testing

When `MTLCreateSystemDefaultDevice()` reports `.metal4`, `MetalTests` runs the
GPU `step`/`fit` kernels and asserts the `ColorGrid` equals
`CPUAutomatonRenderer`'s for binary, 3-color, and right-pinned entries.
`RenderActorTests` asserts the GPU incremental path matches `IncrementalRenderer`
frame for frame (including the partially filled grid mid-run and a scrolling
run's moving window), that the `.window` mapping and a pan match the CPU on a
board ten windows wide, that `restart` reseeds and `setPacing` changes the
rate, that the render actor runs off the main thread, that `drive` advances on
a clock tick, and that `.timed` pacing follows the tick delta. `LayerTests`
compares the `runs` span
compaction with a CPU run-length pass, checks the incremental GPU path's
accumulated spans against a full CPU compaction, and reads the rendered texture
back to check spans are filled with palette colours. `IndicatorTests` checks
the beating rings draw over the background and change with `time`. The
display-link presentation itself needs a screen and is not tested here.
