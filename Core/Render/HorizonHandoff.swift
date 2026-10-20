import Foundation

/// The reveal's horizon row starts where the intro's line ends — a hairline at
/// low opacity on the palette background — and reaches its full height and
/// opacity over the first half second.
public enum HorizonHandoff {
    /// Seconds the horizon row takes to reach full height and opacity.
    public static let duration: TimeInterval = 0.5

    /// 0...1 ramp for the row's height and opacity. The renderer maps 0 to the
    /// intro's ending line and 1 to a full row.
    public static func reveal(elapsed: TimeInterval) -> Float {
        min(max(Float(elapsed / duration), 0), 1)
    }
}
