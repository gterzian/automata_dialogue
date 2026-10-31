import Foundation

/// The reveal's ending: the picture is eaten back onto the horizon row, the
/// line closes into its centre point, and the review moves to the next page.
/// The mask only hides cells — the picture itself never moves or scales, so the
/// automaton is consumed in place rather than shrunk.
public enum RevealEnding {
    /// Seconds the edges take to eat the picture back to the horizon row.
    public static let wipeDuration: TimeInterval = 1.2
    /// Seconds the horizon row takes to close into its centre point.
    public static let lineDuration: TimeInterval = 0.5
    /// Seconds the point holds before the next page appears.
    public static let restDuration: TimeInterval = 0.3

    public static var duration: TimeInterval {
        wipeDuration + lineDuration + restDuration
    }
}

/// Where a driven reveal is in its ending.
public enum RevealEndPhase: Sendable, Equatable {
    /// The pull-back is still running.
    case playing
    /// The picture is being eaten onto the horizon and closed into its point.
    case collapsing
    /// The point has held for its rest beat; the review moves on.
    case settled
}

/// What a frame's mask leaves of the picture: a box in the surface's
/// coordinates (0…1, y down) whose top and bottom edges wander, and whose left
/// and right edges close on the centre point. Every cell outside the box draws
/// as the page, so the picture is eaten rather than rescaled.
public struct RevealMask: Sendable, Equatable {
    public var left: Float
    public var top: Float
    public var right: Float
    public var bottom: Float
    /// Height the top and bottom edges wander, as a fraction of the surface.
    public var wobble: Float
    /// Where that wander starts, so every run eats its picture differently.
    public var phase: Float

    /// The whole picture: no cell is hidden and no edge wanders.
    public static let full = RevealMask(
        left: 0, top: 0, right: 1, bottom: 1, wobble: 0, phase: 0)

    public init(
        left: Float, top: Float, right: Float, bottom: Float,
        wobble: Float, phase: Float
    ) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
        self.wobble = wobble
        self.phase = phase
    }
}

/// One ending's look: how far its edges wander and how much the lower edge
/// trails the upper one, so the picture is eaten from the top down.
struct RevealVariation: Equatable {
    /// The wander, as a fraction of the band the edges have left.
    var wobble: Float
    var phase: Float
    /// Seconds the lower edge trails the upper one.
    var lag: Float

    static func seeded(_ seed: UInt64) -> RevealVariation {
        var draw = SplitMix64(seed: seed)
        return RevealVariation(
            wobble: draw.float(0.02...0.05),
            phase: draw.float(0...Float.pi * 2),
            lag: draw.float(0.05...0.15))
    }
}

/// The ending's timeline. One wall-clock time drives the wipe and the close, so
/// a dropped frame cannot stretch them. The wipe keeps a few grid rows around
/// the horizon rather than one, so the line stays visible at the grid's own
/// resolution, and the close ends on a square point of the same size.
enum RevealTimeline {
    /// Grid rows the finished line spans around the horizon.
    static let lineRows: Float = 3

    struct Frame {
        var mask: RevealMask
        /// True once the point has held for `RevealEnding.restDuration`.
        var resting: Bool
    }

    static func frame(
        time rawTime: Float,
        rows: Int,
        cols: Int,
        variation: RevealVariation
    ) -> Frame {
        let wipe = Float(RevealEnding.wipeDuration)
        let line = Float(RevealEnding.lineDuration)
        let time = min(max(rawTime, 0), wipe + line + Float(RevealEnding.restDuration))

        let rowPitch = 1 / Float(max(1, rows))
        let columnPitch = 1 / Float(max(1, cols))
        let lineHalf = min(0.5, lineRows * rowPitch / 2)
        let pointHalf = min(0.5, lineRows * columnPitch / 2)

        // The upper edge leads; the lower one trails by the run's lag, so the
        // picture reads as eaten from the top down. Both reach the horizon at
        // the end of the wipe.
        let lead = max(0.05, wipe - variation.lag)
        let upper = smoothstep(0, lead, time)
        let lower = smoothstep(variation.lag, wipe, time)

        // The line closes on its centre point after the wipe.
        let close = smoothstep(wipe, wipe + line, time)

        let top = upper * (0.5 - lineHalf)
        let bottom = 1 - lower * (0.5 - lineHalf)
        let left = close * (0.5 - pointHalf)
        let right = 1 - close * (0.5 - pointHalf)
        // The wander fades in with the wipe and follows the band the edges have
        // left: the frame the collapse starts on is the untouched picture, and
        // the finished line is exactly the horizon.
        let wander = variation.wobble * (bottom - top) * smoothstep(0, 0.25, time)

        return Frame(
            mask: RevealMask(
                left: left,
                top: top,
                right: right,
                bottom: bottom,
                wobble: wander,
                phase: variation.phase),
            resting: time >= wipe + line + Float(RevealEnding.restDuration))
    }

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = min(max((x - edge0) / max(edge1 - edge0, 1e-4), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
