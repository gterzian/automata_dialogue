import XCTest
@testable import Core

/// A `FrameSink` that records the GPU-resident frames the actor delivers and
/// lets a test wait for the next one.
private final class RecordingSink: FrameSink, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [RenderFrame] = []
    private var done = false
    private let available = DispatchSemaphore(value: 0)

    func deliver(_ frame: RenderFrame) {
        lock.lock()
        recorded.append(frame)
        lock.unlock()
        available.signal()
    }

    func finish() {
        lock.lock()
        done = true
        lock.unlock()
        available.signal()
    }

    var frames: [RenderFrame] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return done
    }

    func waitForFrame(timeout: TimeInterval = 1) -> RenderFrame? {
        _ = available.wait(timeout: .now() + timeout)
        return frames.last
    }
}

final class FrameSeamTests: XCTestCase {
    func testFixedPacingIgnoresDelta() {
        var remainder = 0.0
        let pacing = RenderPacing.fixed(7)
        XCTAssertEqual(pacing.steps(for: 0.001, remainder: &remainder), 7)
        XCTAssertEqual(pacing.steps(for: 5, remainder: &remainder), 7)
    }

    func testTimedPacingCarriesSubRowRemainder() {
        var remainder = 0.0
        let pacing = RenderPacing.timed(stepsPerSecond: 10)
        // 0.05 s is half a row at 10 rows/s, so the first tick advances none.
        XCTAssertEqual(pacing.steps(for: 0.05, remainder: &remainder), 0)
        // The carried half-row completes on the next tick.
        XCTAssertEqual(pacing.steps(for: 0.05, remainder: &remainder), 1)
        XCTAssertEqual(remainder, 0, accuracy: 1e-9)
        // A full second advances ten rows at once.
        XCTAssertEqual(pacing.steps(for: 1.0, remainder: &remainder), 10)
    }

    func testTimedPacingCapsAndDropsBacklog() {
        var remainder = 0.0
        let pacing = RenderPacing.timed(stepsPerSecond: 1000, maxStepsPerTick: 64)
        XCTAssertEqual(pacing.steps(for: 1.0, remainder: &remainder), 64)
        // The 1000-row delta is clamped instead of carried, so a stalled clock
        // never runs the whole board in one frame.
        XCTAssertEqual(remainder, 0, accuracy: 1e-9)
        XCTAssertEqual(pacing.steps(for: 1.0 / 1000, remainder: &remainder), 1)
    }
}

final class RenderActorTests: XCTestCase {
    func testActorWorkRunsOffMainThreadSerially() async {
        let actor = RenderActor()
        let offMain = await actor.runsOffMainThread()
        let first = await actor.renderThreadID()
        let second = await actor.renderThreadID()
        XCTAssertTrue(offMain)
        XCTAssertEqual(first, second)
        await actor.shutdown()
    }

    func testUnconfiguredActorAdvancesAreNoOps() async throws {
        let actor = RenderActor()
        let frame = try await actor.advance(by: 1)
        XCTAssertNil(frame)
        await actor.shutdown()
    }

    /// A configured run delivers the seed frame as a GPU-resident grid, and
    /// `advance` delivers another.
    func testConfigureDeliversGPUFrames() async throws {
        guard GPUContext.isAvailable else {
            throw XCTSkip("no Metal 4 device")
        }
        let spec = Catalog.spec(id: "E90")!
        let sink = RecordingSink()
        let actor = RenderActor()
        let seed = try await actor.configure(spec: spec, cols: 40, rows: 20, sink: sink)
        XCTAssertEqual(seed.specID, "E90")
        XCTAssertEqual(seed.gpu.cols, 40)
        XCTAssertEqual(seed.gpu.rows, 20)
        XCTAssertEqual(sink.frames.count, 1)

        _ = try await actor.advance(by: 5)
        XCTAssertEqual(sink.frames.count, 2)

        await actor.shutdown()
        XCTAssertTrue(sink.isFinished)
    }

    /// `drive` starts the target's frame loop on the render thread and advances
    /// the run on each frame. A target with no surface still delivers the frames
    /// to the sink, so the test pumps the loop and waits for them.
    func testDriveDeliversOnEachFrame() async throws {
        guard GPUContext.isAvailable else {
            throw XCTSkip("no Metal 4 device")
        }
        let spec = Catalog.spec(id: "E30")!
        let sink = RecordingSink()
        let target = OffscreenTarget(textures: [])
        let actor = RenderActor()
        try await actor.configure(spec: spec, cols: 20, rows: 10, sink: sink)
        XCTAssertEqual(sink.frames.count, 1)
        _ = sink.waitForFrame(timeout: 0.01) // consume the seed frame's signal
        await actor.drive(target: target, pacing: .fixed(5))

        target.tick(1.0 / 30)
        _ = sink.waitForFrame(timeout: 0.5)
        XCTAssertEqual(sink.frames.count, 2)
        let error = await actor.lastError
        XCTAssertNil(error)

        // `stopDriving` stops the target's frame loop, so a later frame
        // delivers nothing.
        await actor.stopDriving()
        target.tick(1.0 / 30)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(sink.frames.count, 2)

        await actor.shutdown()
    }

    /// `restart` returns to frame 0 and, for a `.rand` entry, draws a new seed
    /// row. The sink keeps receiving frames.
    func testRestartDeliversASeedFrame() async throws {
        guard GPUContext.isAvailable else {
            throw XCTSkip("no Metal 4 device")
        }
        let spec = Catalog.spec(id: "E90.rand")!
        let sink = RecordingSink()
        let actor = RenderActor()
        _ = try await actor.configure(spec: spec, cols: 80, rows: 20, sink: sink)
        _ = try await actor.advance(by: 5)
        XCTAssertEqual(sink.frames.count, 2)

        await actor.restart()
        XCTAssertEqual(sink.frames.count, 3)
        await actor.shutdown()
    }

    /// A twin run exposes its step count for the reveal camera and refits both
    /// branches when the camera zooms out.
    func testTwinRunExposesStepsAndRefits() async throws {
        guard GPUContext.isAvailable else {
            throw XCTSkip("no Metal 4 device")
        }
        let spec = Catalog.spec(id: "E90")!
        let sink = RecordingSink()
        let actor = RenderActor()
        let seed = try await actor.configure(
            spec: spec, cols: 40, rows: 21,
            layout: .twin, minimumZoom: 0.25, sink: sink)
        XCTAssertEqual(seed.gpu.cols, 40)
        XCTAssertEqual(seed.gpu.rows, 21)
        let before = await actor.steppedRows
        _ = try await actor.advance(by: 6)
        let after = await actor.steppedRows
        XCTAssertEqual(after, before + 6)

        await actor.setZoom(0.5)
        XCTAssertEqual(sink.frames.last?.gpu.cols, 80)
        XCTAssertEqual(sink.frames.last?.gpu.rows, 41)
        let error = await actor.lastError
        XCTAssertNil(error)
        await actor.shutdown()
    }

    /// `setZoom` refits the run and delivers the new frame, so the reveal
    /// camera's level changes go through the actor.
    func testSetZoomDeliversARefittedFrame() async throws {
        guard GPUContext.isAvailable else {
            throw XCTSkip("no Metal 4 device")
        }
        let spec = Catalog.spec(id: "E90")!
        let sink = RecordingSink()
        let actor = RenderActor()
        _ = try await actor.configure(spec: spec, cols: 40, rows: 20, sink: sink)
        XCTAssertEqual(sink.frames.count, 1)

        await actor.setZoom(2)
        XCTAssertEqual(sink.frames.count, 2)
        let error = await actor.lastError
        XCTAssertNil(error)
        await actor.shutdown()
    }
}
