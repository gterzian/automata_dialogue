import CoreGraphics
import Foundation

/// Display geometry for the animating review window.
///
/// The review window simulates a board much wider than the window (the
/// reference visualizer runs one ten windows wide) and renders only a movable
/// viewport into it, so the pattern keeps evolving after it leaves the first
/// window and the view can pan to follow it. The `LayerRenderer` stretches the
/// small cell grid over the whole drawable.
public enum ViewportGeometry {
    /// Cell edge in points. The reference visualizer advances a cell every 4
    /// screen pixels; at the 2× scale a Retina display uses, 2 points is that
    /// cell, so the pattern shows the visualizer's detail instead of blocks
    /// twice its size.
    public static let minimumCellPoints: CGFloat = 2

    /// How many viewport widths the simulated board spans. The pattern must be
    /// able to leave the viewport and keep going, and the view needs room to
    /// pan, so the board is deliberately much wider than the window.
    public static let boardWindows = 10

    /// Display columns for a window of `size` points.
    public static func columns(size: CGSize) -> Int {
        max(1, Int(max(1, size.width) / minimumCellPoints))
    }

    /// Rows that keep cells square for `cols` columns in a window of `size`.
    public static func rows(size: CGSize, cols: Int) -> Int {
        let width = max(1, size.width)
        let height = max(1, size.height)
        return max(1, Int((height * CGFloat(cols) / width).rounded()))
    }

    /// The simulated board's width: at least `specWidth`, and wide enough that
    /// the viewport is one of `boardWindows` windows across it.
    public static func boardWidth(specWidth: Int, cols: Int) -> Int {
        max(max(1, specWidth), cols * boardWindows)
    }

    /// The first source column the viewport starts at. A right-pinned or
    /// rightmost entry starts at the right edge; everything else starts centred
    /// on the board so the seed is visible and the view can pan either way.
    public static func initialOrigin(
        boardWidth: Int,
        cols: Int,
        start: BoardStart,
        pinRight: Bool
    ) -> Int {
        let maximum = max(0, boardWidth - cols)
        if pinRight { return maximum }
        if case .rightmost = start { return maximum }
        return maximum / 2
    }
}
