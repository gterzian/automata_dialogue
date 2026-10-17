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
    /// dimension falls below one cell. The level snap keeps a gesture from
    /// reallocating the span buffer on every frame.
    func testZoomResizesTheGrid() {
        XCTAssertEqual(ViewportGeometry.zoomedColumns(baseCols: 800, zoom: 1), 800)
        XCTAssertEqual(ViewportGeometry.zoomedColumns(baseCols: 800, zoom: 2), 400)
        XCTAssertEqual(ViewportGeometry.zoomedColumns(baseCols: 800, zoom: 4), 200)
        XCTAssertEqual(ViewportGeometry.zoomedColumns(baseCols: 800, zoom: 0.5), 1600)
        XCTAssertEqual(ViewportGeometry.zoomedRows(baseRows: 500, zoom: 2), 250)
        XCTAssertEqual(ViewportGeometry.zoomedColumns(baseCols: 1, zoom: 4), 1)
        XCTAssertEqual(ViewportGeometry.nearestZoom(1.3), 1.25)
        XCTAssertEqual(ViewportGeometry.nearestZoom(3.0), 3.2)
        XCTAssertEqual(ViewportGeometry.nearestZoom(0.1), ViewportGeometry.minimumZoom)
        XCTAssertEqual(ViewportGeometry.nearestZoom(99), ViewportGeometry.maximumZoom)
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
