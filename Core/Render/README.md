# Core/Render

Turns a `ProgramSpec` into a `ColorGrid` (one `UInt8` palette index per display
cell, row-major) and, on the Metal path, into a GPU buffer. The design's three
seams — **simulation core**, **frame sink** (delivery), **frame clock**
(pacing) — are the target shape. The CPU reference and the sink-independent
GPU simulation exist, `RenderActor` confines the GPU work to a dedicated
thread, and `FrameSink`/`ReadbackSink` deliver finished frames; the on-screen
`LayerSink` and the LED sink remain.

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
  `ReadbackSink` retains the latest frame for a CPU consumer. `FrameClock` is
  the pacing protocol a `CAMetalDisplayLink` implementation will conform to.
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
- The residency set is Metal 4's only residency mechanism; buffers must be
  added and the set committed before use.

## Remaining work

- **`LayerSink`.** A `CAMetalDisplayLink`-driven `FrameSink` that presents a
  `CAMetalLayer` drawable; the app panel currently draws the CPU `CGImage`.
  It supplies the `FrameClock` (a display-link clock) and exploits the three
  frame slots: `ReadbackSink` waits after every commit, so the rotation is
  structural today and the ring only pays off once delivery returns from the
  drawable callback without blocking.
- **App wiring.** `RaterModel` still animates with `IncrementalRenderer` on the
  main actor; it should drive `RenderActor` and keep only finished frames.
- **`LEDSink`** behind the `RATER_SINK_LED` flag.

## Testing

When `MTLCreateSystemDefaultDevice()` reports `.metal4`, `MetalTests` runs the
GPU `step`/`fit` kernels and asserts the `ColorGrid` equals
`CPUAutomatonRenderer`'s for binary, 3-color, and right-pinned entries.
`RenderActorTests` asserts the GPU incremental path matches `IncrementalRenderer`
frame for frame (including the partially filled grid mid-run) and that the
render actor runs off the main thread.
