import Foundation

/// One delivered frame: the fitted grid plus enough run state for a sink to
/// present it or to know when the run has settled. The sink looks the
/// `ProgramSpec` up from the catalog by `specID` (design doc §8: a transcript
/// stores only the id and rebuilds from the catalog), so a frame stays small
/// and `Sendable` across the render actor boundary.
public struct RenderFrame: Sendable {
    /// Catalog id of the entry that produced the frame.
    public let specID: String
    /// Palette index per display cell, row-major.
    public let grid: ColorGrid
    /// Source row currently computed (0 is the seed).
    public let step: Int
    /// Total source rows in the run.
    public let totalSteps: Int
    /// True once `step` has reached the last source row.
    public let settled: Bool
    /// Index of the frame slot that produced this frame (design doc §11.8).
    public let slot: Int

    public init(specID: String, grid: ColorGrid, step: Int, totalSteps: Int, settled: Bool, slot: Int) {
        self.specID = specID
        self.grid = grid
        self.step = step
        self.totalSteps = totalSteps
        self.settled = settled
        self.slot = slot
    }
}
