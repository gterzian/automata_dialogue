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

    /// Hard lower bound on a run's grid zoom. A run never grows the display
    /// grid past the floor this implies, so a degenerate display cannot ask
    /// for an unbounded grid; the reveal's sampling stride carries the zoom
    /// below it (see `sourceStride`).
    public static let minimumZoomLimit = 1.0 / 64
    public static let maximumZoom = 4.0

    /// Largest display grid the reveal allocates. The layer's span buffer holds
    /// one 16-byte span per cell, so this caps it at ~74 MB at the floor.
    public static let maximumGridCells = 4_600_000

    /// The widest zoom-out a display can show without drawing two cells into
    /// one element. The floor is the larger of the surface's one-to-one column
    /// count and the grid's cell budget, clamped to the hard bound.
    public static func zoomFloor(
        baseCols: Int,
        baseRows: Int,
        limits: DisplayLimits
    ) -> Double {
        let columns = Double(max(1, baseCols))
        let rows = Double(max(1, baseRows))
        let byColumns = columns / Double(max(1, limits.maximumColumns))
        let byCells = (columns * rows / Double(max(1, limits.maximumCells))).squareRoot()
        return min(1, max(minimumZoomLimit, max(byColumns, byCells)))
    }

    /// Display columns for a zoomed window: zooming in shrinks the grid so a
    /// board cell covers more display cells, and zooming out grows it so more
    /// board fits. The grid stops at the display floor, where one cell is one
    /// drawable element; past it `sourceStride` samples more source cells per
    /// display cell instead of growing the grid.
    public static func zoomedColumns(baseCols: Int, zoom: Double) -> Int {
        max(1, Int((Double(max(1, baseCols)) / zoom).rounded()))
    }

    /// Display rows for a zoomed window; see `zoomedColumns`.
    public static func zoomedRows(baseRows: Int, zoom: Double) -> Int {
        max(1, Int((Double(max(1, baseRows)) / zoom).rounded()))
    }

    /// Rows for the reveal's twin layout, always odd so the two branches can
    /// share one horizon row. Both branches then start from that exact row and
    /// mirror around it, with no background between them.
    public static func twinRows(baseRows: Int, zoom: Double) -> Int {
        let rows = zoomedRows(baseRows: baseRows, zoom: zoom)
        return rows % 2 == 1 ? rows : max(1, rows - 1)
    }

    /// Source cells a display cell samples once a branch has grown more rows
    /// than its half of the window can show. The camera's mapping always puts
    /// the seed row on the horizon and the newest row on the outer edge, so
    /// display distance `d` from the horizon reads source row `round(d ×
    /// stride)`. At or below the stride of 1 this is the one-to-one mapping;
    /// above it the whole history stays visible at decreasing resolution.
    public static func sourceStride(steps: Int, span: Int) -> Double {
        guard span > 0 else { return 1 }
        return max(1, Double(max(0, steps)) / Double(span))
    }

    /// Source rows from the shared horizon row to each outer edge.
    public static func twinHalfRows(rows: Int) -> Int {
        max(0, (max(1, rows) - 1) / 2)
    }

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

/// What a display can resolve one-to-one. The review window maps one display
/// cell to one element of the surface; a Retina display reports its pixels and
/// an LED wall its addressable elements, so the reveal's zoom floor is a
/// property of the display rather than a constant. `maximumCells` bounds the
/// grid's memory separately from what the surface can show.
public struct DisplayLimits: Sendable, Equatable {
    public var maximumColumns: Int
    public var maximumCells: Int

    public init(
        maximumColumns: Int,
        maximumCells: Int = ViewportGeometry.maximumGridCells
    ) {
        self.maximumColumns = max(1, maximumColumns)
        self.maximumCells = max(1, maximumCells)
    }

    /// A surface that shows one cell per device pixel.
    public static func pixels(
        points: CGFloat,
        scale: CGFloat,
        maximumCells: Int = ViewportGeometry.maximumGridCells
    ) -> DisplayLimits {
        DisplayLimits(
            maximumColumns: max(1, Int((max(1, points) * max(1, scale)).rounded())),
            maximumCells: maximumCells)
    }
}
