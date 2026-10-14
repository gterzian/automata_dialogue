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
