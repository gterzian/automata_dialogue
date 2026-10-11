# Core/Render

Turns a `ProgramSpec` into a `ColorGrid` (one `UInt8` palette index per display
cell, row-major) and, on the Metal path, into a GPU buffer. The design's three
seams — **simulation core**, **frame sink** (delivery), **frame clock**
(pacing) — are built: the CPU reference, the sink-independent GPU simulation,
the dedicated render actor, a readback sink, and the on-screen `LayerSink`
driven by `DisplayLinkClock`. The LED sink remains.

## What exists

- **CPU reference path** (`CPUAutomatonRenderer`, `IncrementalRenderer`) — runs
  the `Core/Programs` reference and fits the rows to a `ColorGrid` /
  `CGImage`. Always available; the correctness reference for the GPU path and
  the backend for the CLI and the current app panel.
- **Metal 4 compute** (`GPUContext`, `MetalSimulation`, `MetalAutomaton`) —
  macOS 26 / Apple silicon. `MTL4CommandQueue`, `MTL4CommandAllocator`, one
  reusable `MTL4CommandBuffer`, a residency set, and the `step_*`/`bump_head`/
  `fit` kernels. `MetalSimulation` is the sink-independent core: it owns the
  history buffer and the GPU-side `head` counter and advances one chunk of
  source rows per `render(chunk:)`, so a caller animates instead of running the
  whole board in one commit. `MetalAutomaton` is the one-shot wrapper.
- **Render seam** (`RenderExecutor`, `RenderActor`, `FrameSink`, `FrameClock`,
  `ReadbackSink`, `SinkFactory`) — `RenderActor` confines the Metal objects to
  a dedicated run-loop thread and delivers `RenderFrame`s to a `FrameSink`;
  `ReadbackSink` retains the latest frame for a CPU consumer. `RenderPacing`
  turns clock ticks into advances: `.fixed` for deterministic tests, `.timed`
  accumulates `Δ × stepsPerSecond` and clamps each tick (design doc §7).
  `RenderActor.makeLayerSink(layer:)` builds a layer sink on the actor's own
  `GPUContext`, so the sink and the simulation share one device, queue, and
  residency set.
- **GPU-resident frames** — a sink that sets
  `wantsGPUResidentFrames` receives `GPUColorGrid` (the simulation's
  `colorBuffer` plus the rows this frame fitted) instead of a CPU `ColorGrid`,
  so the actor skips the readback. `LayerRenderer.render(gpu:)` appends the new
  rows to the spans it already compacted; display rows never change once
  fitted, so the accumulated spans stay valid. A frame with `firstRow == 0`
  starts a run and resets the counter.
- **On-screen sink** (`DisplayLinkClock`, `LayerSink`, `LayerRenderer`) —
  `DisplayLinkClock` conforms to `FrameClock` over `CAMetalDisplayLink`
  (`preferredFrameLatency = 2`); `LayerSink` is a `FrameSink` that owns the
  layer and the clock, and `LayerRenderer` turns a frame into a draw: a `runs`
  kernel compacts each same-colour non-background run into a `Span`, an
  `encode_draw` kernel writes the `MTLDrawPrimitivesIndirectArguments` on the
  GPU, and a render pass clears to the background and draws one instanced quad
  per span. `RenderActor.drive(clock:pacing:)` starts the clock on the render
  thread.
- **Fit** (`Fit`) — the one geometry rule both paths use.

Both paths converge on the same `ColorGrid`; the readback test compares them.

## Geometry and fit

`Fit` maps each display column to a block of source cells: nearest for
`k == 1`, majority vote for `k > 1`, the rightmost window for `pinRight`
(E110). A display column that reaches past the board reads background; it never
wraps to the left edge.

Remaining work: majority vote erases sparse single-cell features when a board
is downsampled (E90's Sierpinski seeds at a reduced width). Boards narrower
than the panel use `k = 1` (upscale), so this only affects the 6101-wide
entries, which are dense. If a sparse entry ever needs downsampling, revisit
`Fit` and the Metal `fit` kernel together.

## Metal 4 gotchas

- **The argument table is live at GPU execution time.** Rebinding one table's
  addresses between encoded dispatches makes every dispatch resolve to the
  final address. The step kernels therefore read the current row from a
  GPU-side `head` counter that a 1-thread `bump_head` kernel advances, so all
  argument tables have constant bindings (design doc §11.9, the "one-thread
  kernel advances a GPU-side head counter" fallback).
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

- **App wiring.** `RaterModel` still animates with `IncrementalRenderer` on the
  main actor and draws a `CGImage`; it should host a `CAMetalLayer`, ask the
  actor for a `LayerSink` with `makeLayerSink(layer:)`, `configure` the actor
  with it, and `drive` its clock with `.timed`. The app target cannot be
  type-checked in this sandbox (the SwiftUI macro plugin is blocked), so this
  is untested here. The CLI's `rate --show` exercises this same wiring
  (`CLI/README.md`).
- **`LEDSink`** behind the `RATER_SINK_LED` flag. Its geometry, colour order,
  and transport are open decisions (§11.13), so it waits on hardware.

A sink that receives GPU-resident frames must read the buffer only on the
render actor and must treat `firstRow == 0` as a new run, because the spans
accumulate across frames.

## Testing

When `MTLCreateSystemDefaultDevice()` reports `.metal4`, `MetalTests` runs the
GPU `step`/`fit` kernels and asserts the `ColorGrid` equals
`CPUAutomatonRenderer`'s for binary, 3-color, and right-pinned entries.
`RenderActorTests` asserts the GPU incremental path matches `IncrementalRenderer`
frame for frame (including the partially filled grid mid-run), that the render
actor runs off the main thread, that `drive` advances on a clock tick, and that
`.timed` pacing follows the tick delta. `LayerTests` compares the `runs` span
compaction with a CPU run-length pass, checks the incremental GPU path's
accumulated spans against a full CPU compaction, and reads the rendered texture
back to check spans are filled with palette colours. The display-link
presentation itself needs a screen and is not tested here.
