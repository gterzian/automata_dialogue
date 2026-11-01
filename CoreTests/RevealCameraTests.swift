import XCTest
@testable import Core

/// The reveal camera's pull-back: it opens on a close-up of the seed, only
/// ever zooms out, matches the branches' growth one for one once the close-up
/// is spent, and keeps pulling back below the display floor so the whole
/// history stays in view.
final class RevealCameraTests: XCTestCase {
    private let branchRows = 199

    private func zoom(steps: Int) -> Double {
        RevealCamera.zoom(steps: steps, branchRows: branchRows)
    }

    func testStartsOnTheCloseUp() {
        XCTAssertEqual(zoom(steps: 0), RevealCamera.startZoom)
        XCTAssertGreaterThan(RevealCamera.startZoom, 1)
    }

    /// The close-up holds for the rows the branch can show at that scale, and
    /// the pull-back starts on the step that needs more.
    func testCloseUpHoldsWhileTheBranchHasRoom() {
        let rowsAtCloseUp = Int(Double(branchRows) / RevealCamera.startZoom)
        XCTAssertEqual(zoom(steps: rowsAtCloseUp - 1), RevealCamera.startZoom)
        XCTAssertLessThan(zoom(steps: rowsAtCloseUp), RevealCamera.startZoom)
    }

    func testMonotoneAndBounded() {
        var previous = RevealCamera.startZoom
        for steps in 0...1_200 {
            let zoom = zoom(steps: steps)
            XCTAssertLessThanOrEqual(zoom, previous, "zoom must not increase at step \(steps)")
            XCTAssertGreaterThan(zoom, 0)
            XCTAssertLessThanOrEqual(zoom, RevealCamera.startZoom)
            previous = zoom
        }
    }

    /// The grid's column count stays even at every step, so the centre column
    /// keeps the seed half a cell off the centre line. An odd count would
    /// centre the seed, and the whole pattern would snap sideways as the zoom
    /// crossed that count.
    func testColumnsStayEvenAtEveryStep() {
        for steps in 0...1_200 {
            let cols = ViewportGeometry.zoomedColumns(
                baseCols: 720, zoom: zoom(steps: steps))
            XCTAssertEqual(cols % 2, 0, "step \(steps)")
        }
    }

    /// Past the close-up the rows a branch has grown track the camera one for
    /// one, so the pattern grows at a constant screen rate instead of jumping
    /// levels.
    func testMatchesTheGrowthRate() {
        for steps in 0...750 {
            guard zoom(steps: steps) < RevealCamera.startZoom else { continue }
            XCTAssertEqual(
                zoom(steps: steps) * Double(steps + 1), Double(branchRows),
                accuracy: 1e-9, "step \(steps)")
        }
    }

    /// Past the display floor the camera keeps pulling back: the fit samples
    /// the history at a coarser stride instead of the zoom holding and newer
    /// rows pushing older ones out through the horizon.
    func testKeepsPullingBackBelowTheDisplayFloor() {
        let floor = 0.25
        let floorSteps = Int((Double(branchRows) / floor).rounded()) - 1
        XCTAssertEqual(zoom(steps: floorSteps), floor, accuracy: 1e-9)
        XCTAssertEqual(zoom(steps: floorSteps + Int(Double(branchRows) / floor)),
                       floor / 2, accuracy: 1e-9)
    }

    func testDegenerateBranchKeepsTheCloseUp() {
        XCTAssertEqual(
            RevealCamera.zoom(steps: 100, branchRows: 0), RevealCamera.startZoom)
    }

    /// The reveal's driving rate opens at the paced rate and grows by the
    /// setup's per-step growth, which itself accelerates each step, so the
    /// pull-back starts slowly and compounds super-exponentially.
    func testSpeedScaleStartsSteadyAndAcceleratesPerStep() {
        let steady = RevealSetup(branchRows: branchRows)
        XCTAssertEqual(steady.speedScale(atStep: 0), 1)
        XCTAssertEqual(steady.speedScale(atStep: 500), 1)

        // With a steady acceleration the growth is the plain per-step one.
        let growing = RevealSetup(
            branchRows: branchRows, speedGrowthPerStep: 1.01)
        XCTAssertEqual(growing.speedScale(atStep: 0), 1)
        XCTAssertEqual(
            growing.speedScale(atStep: 100), pow(1.01, 100), accuracy: 1e-9)

        // The growth compounds with itself: the log growth of step n is the
        // opening growth raised to the acceleration's nth power.
        let accelerating = RevealSetup(
            branchRows: branchRows, speedGrowthPerStep: 1.001,
            speedGrowthAcceleration: 1.01)
        XCTAssertEqual(accelerating.speedScale(atStep: 0), 1)
        XCTAssertEqual(
            log(accelerating.speedScale(atStep: 1)), log(1.001), accuracy: 1e-12)
        XCTAssertEqual(
            log(accelerating.speedScale(atStep: 101)
                / accelerating.speedScale(atStep: 100)),
            log(1.001) * pow(1.01, 100), accuracy: 1e-12)
    }
}
