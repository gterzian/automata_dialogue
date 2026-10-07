import Foundation
import Metal

/// One-shot convenience over `MetalSimulation`: runs a catalog entry to
/// completion on the Metal 4 compute path and reads the result back. The GPU
/// kernels must produce the same grid as `CPUAutomatonRenderer`; `MetalTests`
/// asserts that. Animated callers (the app, the render actor) drive
/// `MetalSimulation` directly so they can advance a chunk at a time.
@available(macOS 26.0, *)
public enum MetalAutomaton {
    public static func colorGrid(
        spec: ProgramSpec,
        cols: Int,
        rows: Int,
        steps: Int? = nil,
        context: GPUContext
    ) throws -> ColorGrid {
        let simulation = try MetalSimulation(spec: spec, cols: cols, rows: rows, steps: steps, context: context)
        return try simulation.render(chunk: simulation.totalSteps - 1)
    }
}
