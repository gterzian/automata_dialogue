import XCTest
@testable import Core

/// The reveal camera's pull-back: it starts at 1×, never zooms in, matches the
/// branches' growth continuously, and stays at the floor once the region starts
/// clipping older rows.
final class RevealCameraTests: XCTestCase {
    private let floor = 0.25
    private let branchRows = 199

    private func zoom(steps: Int) -> Double {
        RevealCamera.zoom(steps: steps, branchRows: branchRows, floor: floor)
    }

    func testStartsAtActualSize() {
        XCTAssertEqual(zoom(steps: 0), 1.0)
    }

    func testMonotoneAndBounded() {
        var previous = 1.0
        for steps in 0...1_200 {
            let zoom = zoom(steps: steps)
            XCTAssertLessThanOrEqual(zoom, previous, "zoom must not increase at step \(steps)")
            XCTAssertGreaterThanOrEqual(zoom, floor)
            XCTAssertLessThanOrEqual(zoom, 1.0)
            previous = zoom
        }
    }

    func testNewestRowIsVisibleAboveTheFloor() {
        for steps in 0...800 {
            let zoom = zoom(steps: steps)
            guard zoom > floor else { continue }
            XCTAssertGreaterThanOrEqual(
                ViewportGeometry.zoomedRows(baseRows: branchRows, zoom: zoom), steps + 1,
                "step \(steps) at \(zoom) must still show the newest row")
        }
    }

    /// While pulling back, the rows a branch shows track its growth one for one,
    /// so the pattern grows at a constant screen rate instead of jumping levels.
    func testMatchesTheGrowthRate() {
        for steps in 0...750 {
            let zoom = zoom(steps: steps)
            guard zoom > floor, zoom < 1 else { continue }
            XCTAssertEqual(
                Double(ViewportGeometry.zoomedRows(baseRows: branchRows, zoom: zoom)),
                Double(steps + 1), accuracy: 0.001)
        }
    }

    func testHoldsTheFloorOnceTheGrowthFits() {
        let steps = Int((Double(branchRows) / floor).rounded(.up)) - 1
        XCTAssertEqual(zoom(steps: steps), floor)
        for later in steps...(steps + 500) {
            XCTAssertEqual(zoom(steps: later), floor)
        }
    }

    func testDegenerateBranchStaysAtActualSize() {
        XCTAssertEqual(
            RevealCamera.zoom(steps: 100, branchRows: 0, floor: floor), 1.0)
    }
}
