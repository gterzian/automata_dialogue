import Foundation

/// The reveal's ending: the automaton is closed inside the same organic circle
/// the intro uses and falls into a single ink dot, then the review moves to the
/// next page. The toned grid the pull-back stops on is sampled through the
/// circle, so the picture and the dot are one draw.
public enum RevealEnding {
    /// Seconds the circle takes to close from the picture onto the dot.
    public static let collapseDuration: TimeInterval = 1.0
    /// Seconds the dot holds before the next page appears.
    public static let restDuration: TimeInterval = 0.5

    public static var duration: TimeInterval {
        collapseDuration + restDuration
    }
}

/// Where a driven reveal is in its ending.
public enum RevealEndPhase: Sendable, Equatable {
    /// The pull-back is still running.
    case playing
    /// The circle is closing the picture into its dot.
    case collapsing
    /// The dot has held for its rest beat; the review moves on.
    case settled
}

/// How the ending transforms the picture. Every field is inert in `.full`, so a
/// frame with that mask draws the untouched grid; the reveal's ending supplies
/// the fields from `RevealTimeline`. The picture's limb is a circle on the
/// surface, and the renderer keeps the dot's soft edge at least a couple of
/// pixels wide so a small surface still shows it.
public struct RevealMask: Sendable, Equatable {
    /// Scale of the picture about the centre: 1 is the whole picture and
    /// `RevealTimeline.dotScale` is the dot it closes into.
    public var scale: Float
    /// The fall's progress: darkens the picture and turns it into ink as the
    /// circle closes.
    public var fall: Float
    /// Limb erosion as a fraction of the visible radius, so the circle closes
    /// along an edge that wanders.
    public var wobble: Float
    /// Where the limb's erosion starts, so no two endings close alike.
    public var phase: Float
    /// Seconds into the ending, so the limb, the smoke, and the grain move.
    public var time: Float
    /// Film-grain strength over the picture's dark areas.
    public var grain: Float

    /// The untouched picture: no fall or erosion.
    public static let full = RevealMask()

    public init(
        scale: Float = 1,
        fall: Float = 0,
        wobble: Float = 0,
        phase: Float = 0,
        time: Float = 0,
        grain: Float = 0
    ) {
        self.scale = scale
        self.fall = fall
        self.wobble = wobble
        self.phase = phase
        self.time = time
        self.grain = grain
    }
}

/// One ending's look: how the circle's limb erodes and how strongly the grain
/// reads.
struct RevealVariation: Equatable {
    /// Limb erosion as a fraction of the visible radius.
    var wobble: Float
    var phase: Float
    /// Film-grain strength.
    var grain: Float

    static func seeded(_ seed: UInt64) -> RevealVariation {
        var draw = SplitMix64(seed: seed)
        return RevealVariation(
            wobble: draw.float(0.04...0.10),
            phase: draw.float(0...Float.pi * 2),
            grain: draw.float(0.025...0.05))
    }
}

/// The ending's timeline. One wall-clock time drives the whole fall, so a
/// dropped frame cannot stretch it: the circle accelerates inward and the dot
/// holds for the rest beat.
enum RevealTimeline {
    /// Scale of the picture when the circle has closed: the single ink dot.
    static let dotScale: Float = 0.005

    struct Frame {
        var mask: RevealMask
        /// True once the dot has held for `RevealEnding.restDuration`.
        var resting: Bool
    }

    static func frame(time rawTime: Float, variation: RevealVariation) -> Frame {
        let collapse = Float(RevealEnding.collapseDuration)
        let rest = Float(RevealEnding.restDuration)
        let total = collapse + rest
        let time = min(max(rawTime, 0), total)

        // The circle accelerates inward: the scale drops as the square of the
        // fall's progress, so the picture hangs at its full extent and then
        // rushes into the dot.
        let fall = smoothstep(0, collapse, time)
        let drop = fall * fall
        let scale = 1 - (1 - dotScale) * drop

        return Frame(
            mask: RevealMask(
                scale: scale,
                fall: fall,
                // The limb starts wandering only once the circle has left the
                // surface's edge, so the full frame's border stays still.
                wobble: variation.wobble * smoothstep(0.15, 0.5, fall),
                phase: variation.phase,
                time: time,
                grain: variation.grain * smoothstep(0, 0.15, time)),
            resting: time >= total)
    }

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = min(max((x - edge0) / max(edge1 - edge0, 1e-4), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
