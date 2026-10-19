import Foundation

/// The reveal's pull-back. The camera zooms continuously so the rows a branch
/// has grown always fill its half of the window: as the step count rises, the
/// zoom falls at the same rate, and it holds at the run's floor once the region
/// starts clipping older rows.
public enum RevealCamera {
    /// The zoom that shows `steps + 1` rows in one branch. Never zooms in past
    /// 1× and never goes below `floor`.
    public static func zoom(steps: Int, branchRows: Int, floor: Double) -> Double {
        guard branchRows > 0 else { return 1.0 }
        let needed = Double(max(1, steps + 1))
        return min(1.0, max(floor, Double(branchRows) / needed))
    }
}

/// The camera settings a driven run applies on each clock tick.
public struct RevealSetup: Sendable, Equatable {
    /// Rows from the shared horizon to each outer edge.
    public var branchRows: Int
    /// Widest zoom-out this run allows.
    public var floor: Double

    public init(branchRows: Int, floor: Double) {
        self.branchRows = branchRows
        self.floor = floor
    }
}
