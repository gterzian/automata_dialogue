import XCTest
@testable import Core

final class ViewportTests: XCTestCase {
    func testGridSizesCellsToTheWindow() {
        let size = CGSize(width: 1600, height: 1000)
        XCTAssertEqual(ViewportGeometry.columns(size: size), 800)
        XCTAssertEqual(ViewportGeometry.rows(size: size, cols: 800), 500)
        XCTAssertEqual(ViewportGeometry.rows(size: size, cols: 161), 101)
    }

    /// The simulated board is much wider than the viewport, so the pattern can
    /// leave the first view and the view has room to pan; a catalog board wider
    /// than that is kept.
    func testBoardIsMuchWiderThanTheViewport() {
        XCTAssertEqual(ViewportGeometry.boardWidth(specWidth: 161, cols: 800), 8000)
        XCTAssertEqual(ViewportGeometry.boardWidth(specWidth: 401, cols: 800), 8000)
        XCTAssertEqual(ViewportGeometry.boardWidth(specWidth: 6101, cols: 800), 8000)
        XCTAssertEqual(ViewportGeometry.boardWidth(specWidth: 9001, cols: 800), 9001)
    }

    func testInitialOriginCentresOrPins() {
        XCTAssertEqual(
            ViewportGeometry.initialOrigin(boardWidth: 8000, cols: 800, start: .center, pinRight: false), 3600)
        XCTAssertEqual(
            ViewportGeometry.initialOrigin(boardWidth: 8000, cols: 800, start: .rightmost, pinRight: true), 7200)
        XCTAssertEqual(
            ViewportGeometry.initialOrigin(boardWidth: 321, cols: 800, start: .center, pinRight: false), 0)
    }

    /// A zoom scales the display grid: in shrinks it, out grows it, and neither
    /// dimension falls below one cell. The reveal snaps to levels so it does
    /// not reallocate the span buffer every frame.
    func testZoomResizesTheGrid() {
        XCTAssertEqual(ViewportGeometry.zoomedColumns(baseCols: 800, zoom: 1), 800)
        XCTAssertEqual(ViewportGeometry.zoomedColumns(baseCols: 800, zoom: 2), 400)
        XCTAssertEqual(ViewportGeometry.zoomedColumns(baseCols: 800, zoom: 4), 200)
        XCTAssertEqual(ViewportGeometry.zoomedColumns(baseCols: 800, zoom: 0.5), 1600)
        XCTAssertEqual(ViewportGeometry.zoomedRows(baseRows: 500, zoom: 2), 250)
        XCTAssertEqual(ViewportGeometry.zoomedColumns(baseCols: 1, zoom: 4), 1)
    }

    /// The reveal's floor is the widest zoom-out the surface can show one cell
    /// per element, bounded by the grid's cell budget.
    func testZoomFloorFollowsTheDisplay() {
        let retina = DisplayLimits(maximumColumns: 2880)
        XCTAssertEqual(
            ViewportGeometry.zoomFloor(baseCols: 720, baseRows: 400, limits: retina),
            0.25, accuracy: 1e-3)
        let plain = DisplayLimits(maximumColumns: 1440)
        XCTAssertEqual(
            ViewportGeometry.zoomFloor(baseCols: 720, baseRows: 400, limits: plain),
            0.5, accuracy: 1e-3)
        // A tiny surface cannot zoom out at all.
        XCTAssertEqual(
            ViewportGeometry.zoomFloor(baseCols: 720, baseRows: 400,
                                       limits: DisplayLimits(maximumColumns: 100)),
            1, accuracy: 1e-9)
        // The cell budget wins when the surface could show an even wider grid.
        XCTAssertEqual(
            ViewportGeometry.zoomFloor(
                baseCols: 720, baseRows: 400,
                limits: DisplayLimits(maximumColumns: 100_000, maximumCells: 4_600_000)),
            0.25, accuracy: 1e-3)
        XCTAssertEqual(
            DisplayLimits.pixels(points: 1440, scale: 2).maximumColumns, 2880)
        // A fixed-resolution surface reports its own elements, so the floor
        // follows the panel rather than a screen's pixels.
        let panel = DisplayLimits.elements(columns: 64)
        XCTAssertEqual(panel.maximumColumns, 64)
        // A grid half the panel's width can zoom out until one cell is two
        // elements wide.
        XCTAssertEqual(
            ViewportGeometry.zoomFloor(baseCols: 32, baseRows: 18, limits: panel),
            0.5, accuracy: 1e-3)
        // A grid already wider than the panel cannot zoom out at all.
        XCTAssertEqual(
            ViewportGeometry.zoomFloor(baseCols: 128, baseRows: 72, limits: panel),
            1, accuracy: 1e-9)
        XCTAssertEqual(DisplayLimits.elements(columns: 0).maximumColumns, 1)
    }

    /// The twin grid is odd so exactly one row sits on the horizon, and both
    /// branches measure the same number of rows to their outer edges.
    func testTwinRowsShareOneHorizon() {
        XCTAssertEqual(ViewportGeometry.twinRows(baseRows: 400, zoom: 1), 399)
        XCTAssertEqual(ViewportGeometry.twinRows(baseRows: 401, zoom: 1), 401)
        XCTAssertEqual(ViewportGeometry.twinRows(baseRows: 401, zoom: 0.5), 801)
        XCTAssertEqual(ViewportGeometry.twinHalfRows(rows: 399), 199)
        XCTAssertEqual(ViewportGeometry.twinHalfRows(rows: 401), 200)
    }

    /// Below the display floor the camera keeps pulling back by sampling the
    /// history at a coarser stride, so the whole history stays in view instead
    /// of older rows leaving through the horizon.
    func testSourceStrideKeepsTheWholeHistoryInView() {
        XCTAssertEqual(ViewportGeometry.sourceStride(steps: 0, span: 20), 1)
        XCTAssertEqual(ViewportGeometry.sourceStride(steps: 10, span: 20), 1)
        XCTAssertEqual(ViewportGeometry.sourceStride(steps: 20, span: 20), 1)
        XCTAssertEqual(ViewportGeometry.sourceStride(steps: 40, span: 20), 2)
        XCTAssertEqual(ViewportGeometry.sourceStride(steps: 100, span: 20), 5)
        XCTAssertEqual(ViewportGeometry.sourceStride(steps: 40, span: 0), 1)
        // The newest row lands on the outer edge at every stride.
        let span = 20
        for steps in [25, 40, 100, 1_000] {
            let stride = ViewportGeometry.sourceStride(steps: steps, span: span)
            XCTAssertEqual((Double(span) * stride).rounded(), Double(steps))
        }
    }
}

/// The pan anchor is computed from the `BoardStart` (mirroring the GPU
/// `seed_row` kernel), so it must match each seed shape.
final class SeedColumnTests: XCTestCase {
    func testLeadingColumnMatchesSeedShapes() {
        XCTAssertEqual(MetalSimulation.leadColumn(start: .center, width: 100, colors: 2, rate: 1), 50)
        XCTAssertEqual(MetalSimulation.leadColumn(start: .rightmost, width: 100, colors: 2, rate: 1), 99)
        XCTAssertEqual(MetalSimulation.leadColumn(start: .block([1, 1, 0, 0]), width: 100, colors: 2, rate: 1), 97)
        // 195 is 0b11000011, most significant digit first from the center.
        XCTAssertEqual(
            MetalSimulation.leadColumn(start: .seed(number: 195, colors: 2), width: 64, colors: 2, rate: 1), 39)
        // A fixed entry has no follow rate, so the anchor is irrelevant.
        XCTAssertEqual(MetalSimulation.leadColumn(start: .center, width: 100, colors: 2, rate: 0), 0)
    }
}
