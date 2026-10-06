# Core/Render

Turns a `ProgramSpec` into a `ColorGrid` (one `UInt8` palette index per display
cell, row-major) and, on the Metal path, into a GPU buffer. The design's three
seams — **simulation core**, **frame sink** (delivery), **frame clock**
(pacing) — are the target shape; today the compute and CPU delivery exist and
the sink/clock protocols are remaining work.

## What exists

- **CPU reference path** (`CPUAutomatonRenderer`, `IncrementalRenderer`) — runs
  the `Core/Programs` reference and fits the rows to a `ColorGrid` /
  `CGImage`. Always available; the correctness reference for the GPU path and
  the backend for the CLI and the current app panel.
- **Metal 4 compute** (`GPUContext`, `MetalAutomaton`) — macOS 26 / Apple
  silicon. `MTL4CommandQueue`, `MTL4CommandAllocator`, one reusable
  `MTL4CommandBuffer`, a residency set, and the `step_*`/`bump_head`/`fit`
  kernels. Shader source is compiled at startup from a string
  (`ShaderSource.simulation`) since SwiftPM cannot build a `.metallib`.
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
- Swift names differ from the ObjC selectors: `device.makeMTL4CommandQueue()`;
  `device.makeCompiler(descriptor:)` and `device.makeResidencySet(descriptor:)`
  throw; `compiler.makeLibrary/makeComputePipelineState(descriptor:)`;
  `command.makeComputeCommandEncoder()`; `table.setAddress(_:index:)`;
  `encoder.dispatchThreads(threadsPerGrid:threadsPerThreadgroup:)`.
- The residency set is Metal 4's only residency mechanism; buffers must be
  added and the set committed before use.

## Remaining work

- **Render actor / thread.** Metal objects must be confined to one actor on a
  dedicated run loop; today `MetalAutomaton` runs synchronously on the caller.
- **Frame sink and clock seams** (`FrameSink`, `FrameClock`, `ReadbackSink`,
  `SinkFactory`) and the frame-slot ring (three allocators, buffers, ICBs).
- **`LayerSink`.** A `CAMetalDisplayLink`-driven sink that presents a
  `CAMetalLayer` drawable; the app panel currently draws the CPU `CGImage`.
- **`LEDSink`** behind the `RATER_SINK_LED` flag.

## Testing

When `MTLCreateSystemDefaultDevice()` reports `.metal4`, `MetalTests` runs the
GPU `step`/`fit` kernels and asserts the `ColorGrid` equals
`CPUAutomatonRenderer`'s for binary, 3-color, and right-pinned entries.
