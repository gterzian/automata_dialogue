import Foundation
import Metal

/// A `ColorGrid` that stays on the GPU plus the display rows written since the
/// previous frame, so a sink that can bind the buffer directly skips the
/// per-frame CPU readback.
///
/// The buffer belongs to the live `MetalSimulation`; a sink may read it only on
/// the render actor, and a reconfigured run replaces it.
public struct GPUColorGrid: @unchecked Sendable {
    public let buffer: any MTLBuffer
    public let cols: Int
    public let rows: Int
    /// First display row written by this frame; `rowCount` rows follow it.
    public let firstRow: Int
    public let rowCount: Int

    public init(buffer: any MTLBuffer, cols: Int, rows: Int, firstRow: Int, rowCount: Int) {
        self.buffer = buffer
        self.cols = cols
        self.rows = rows
        self.firstRow = firstRow
        self.rowCount = rowCount
    }

    /// True when the frame begins a run (row 0), so a sink must discard spans it
    /// accumulated for the previous run.
    public var startsRun: Bool { firstRow == 0 }
}

/// One delivered frame: the fitted grid plus enough run state for a sink to
/// present it or to know when the run has settled. The sink looks the
/// `ProgramSpec` up from the catalog by `specID` (a transcript stores only the
/// id and rebuilds from the catalog), so a frame stays small
/// and `Sendable` across the render actor boundary.
///
/// Exactly one of `grid` and `gpu` is set, chosen by
/// `FrameSink.wantsGPUResidentFrames`: the CPU path reads the grid back, the GPU
/// path hands over the simulation's buffer.
public struct RenderFrame: Sendable {
    /// Catalog id of the entry that produced the frame.
    public let specID: String
    /// Palette index per display cell, row-major, for a CPU sink.
    public let grid: ColorGrid?
    /// The simulation's GPU color buffer and this frame's new rows, for a
    /// GPU-resident sink.
    public let gpu: GPUColorGrid?
    /// Source row currently computed (0 is the seed).
    public let step: Int
    /// Total source rows in the run.
    public let totalSteps: Int
    /// True once `step` has reached the last source row.
    public let settled: Bool
    public let slot: Int

    public init(
        specID: String,
        grid: ColorGrid? = nil,
        gpu: GPUColorGrid? = nil,
        step: Int,
        totalSteps: Int,
        settled: Bool,
        slot: Int
    ) {
        self.specID = specID
        self.grid = grid
        self.gpu = gpu
        self.step = step
        self.totalSteps = totalSteps
        self.settled = settled
        self.slot = slot
    }
}
