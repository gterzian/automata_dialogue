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

/// The camera settings and the row-rate curve a driven run applies on each
/// clock tick.
public struct RevealSetup: Sendable, Equatable {
    /// Rows from the shared horizon to each outer edge at 1×; the camera's
    /// reference span.
    public var branchRows: Int
    /// How much the row rate grows at the opening step: 1.001 is +0.1%. 1 keeps
    /// the paced rate; the growth is the same every step until
    /// `speedGrowthAcceleration` changes it.
    public var speedGrowthPerStep: Double
    /// How much that per-step growth itself multiplies each step. 1 keeps the
    /// growth constant; above 1 the growth compounds with itself, so the rate
    /// rises super-exponentially.
    public var speedGrowthAcceleration: Double

    public init(
        branchRows: Int,
        speedGrowthPerStep: Double = 1,
        speedGrowthAcceleration: Double = 1
    ) {
        self.branchRows = branchRows
        self.speedGrowthPerStep = speedGrowthPerStep
        self.speedGrowthAcceleration = speedGrowthAcceleration
    }

    /// The row-rate multiplier once the run has grown `steps` source rows: the
    /// per-step growth is `speedGrowthPerStep` raised to
    /// `speedGrowthAcceleration^step`, and the multiplier accumulates those
    /// growths. The first row runs at the paced rate, so the reveal opens at
    /// the speed a steady run would show and accelerates from there.
    public func speedScale(atStep steps: Int) -> Double {
        guard steps > 0 else { return 1 }
        guard speedGrowthPerStep != 1 else { return 1 }
        let steps = Double(steps)
        // The sum of the first `steps` powers of the acceleration: each step
        // grows the rate by `speedGrowthPerStep^(acceleration^step)`.
        let exponent: Double
        if speedGrowthAcceleration == 1 {
            exponent = steps
        } else {
            exponent = (pow(speedGrowthAcceleration, steps) - 1)
                / (speedGrowthAcceleration - 1)
        }
        return pow(speedGrowthPerStep, exponent)
    }
}
