import Foundation

/// The reveal's pull-back. The camera zooms continuously so the rows a branch
/// has grown always fill its half of the window: as the step count rises, the
/// zoom falls at the same rate. Past the display's one-cell-per-element floor
/// the fit reduces a wider block of the history per cell, so the whole growth
/// stays in view at decreasing resolution. `RenderActor` ends the run once that
/// sampling spans the whole simulated board, because a wider window would
/// sample columns off the board.
public enum RevealCamera {
    /// The zoom the reveal opens at: one display cell is this many times the
    /// window's base cell, so the run starts as a close-up of the seed and the
    /// pull-back carries it out to the branches' own scale. It is the closest
    /// zoom a run may ask for (`ViewportGeometry.maximumZoom`), one cell
    /// covering eight base cells.
    public static let startZoom = ViewportGeometry.maximumZoom

    /// The zoom that shows `steps + 1` rows in one branch, never past the
    /// close-up the reveal opens at. Below the display floor the value only
    /// drives the sampling stride.
    public static func zoom(steps: Int, branchRows: Int) -> Double {
        guard branchRows > 0 else { return startZoom }
        return min(startZoom, Double(branchRows) / Double(max(1, steps + 1)))
    }
}

/// The camera settings and the row-rate growth a driven run applies on each
/// clock tick.
public struct RevealSetup: Sendable, Equatable {
    /// Rows from the shared horizon to each outer edge at 1×; the camera's
    /// reference span.
    public var branchRows: Int
    /// How much the row rate grows per source row: 1.001 is +0.1%, so the
    /// pull-back starts slow and speeds up a little as it goes. 1 keeps the
    /// paced rate.
    public var speedGrowthPerStep: Double

    public init(branchRows: Int, speedGrowthPerStep: Double = 1) {
        self.branchRows = branchRows
        self.speedGrowthPerStep = speedGrowthPerStep
    }

    /// The row-rate multiplier once the run has grown `steps` source rows.
    public func speedScale(atStep steps: Int) -> Double {
        guard steps > 0, speedGrowthPerStep != 1 else { return 1 }
        return pow(speedGrowthPerStep, Double(steps))
    }

    /// The opening rows per second that make growing `steps` source rows last
    /// `duration` seconds under this curve: each row takes `1 / rate` at the
    /// rate it is grown at, and their sum is the pull-back's length.
    public func openingRowsPerSecond(steps: Int, duration: TimeInterval) -> Double {
        let count = Double(max(1, steps))
        let seconds = max(duration, 1e-3)
        guard speedGrowthPerStep != 1 else { return count / seconds }
        // The sum of `g^-n` over the run, in closed form.
        let growth = speedGrowthPerStep
        let weighted = (1 - pow(growth, -count)) / (1 - 1 / growth)
        return weighted / seconds
    }
}
