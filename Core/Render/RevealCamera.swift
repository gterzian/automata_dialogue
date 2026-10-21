import Foundation

/// The reveal's pull-back. The camera zooms continuously so the rows a branch
/// has grown always fill its half of the window: as the step count rises, the
/// zoom falls at the same rate. It never stops: past the display's
/// one-cell-per-element floor the fit samples the history at a coarser stride,
/// so the whole growth stays in view at decreasing resolution.
public enum RevealCamera {
    /// The zoom that shows `steps + 1` rows in one branch. Never zooms in past
    /// 1×; below the display floor the value only drives the sampling stride.
    public static func zoom(steps: Int, branchRows: Int) -> Double {
        guard branchRows > 0 else { return 1.0 }
        return min(1.0, Double(branchRows) / Double(max(1, steps + 1)))
    }
}

/// The camera settings a driven run applies on each clock tick.
public struct RevealSetup: Sendable, Equatable {
    /// Rows from the shared horizon to each outer edge at 1×; the camera's
    /// reference span.
    public var branchRows: Int

    public init(branchRows: Int) {
        self.branchRows = branchRows
    }
}
