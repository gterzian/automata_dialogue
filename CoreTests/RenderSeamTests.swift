import XCTest
@testable import Core

/// A `FrameClock` the test drives by hand. Lives here rather than in `Core`
/// because its only purpose is to advance a test deterministically.
private final class ManualClock: FrameClock, @unchecked Sendable {
    private var tick: (@Sendable (TimeInterval) -> Void)?

    func start(_ tick: @escaping @Sendable (TimeInterval) -> Void) {
        self.tick = tick
    }

    func stop() {
        tick = nil
    }

    func pump(_ delta: TimeInterval) {
        tick?(delta)
    }
}

private final class DeltaBox: @unchecked Sendable {
    var deltas: [TimeInterval] = []
}

final class FrameSeamTests: XCTestCase {
    func testReadbackSinkRetainsLatestFrame() {
        let sink = ReadbackSink()
        let first = RenderFrame(specID: "E90", grid: ColorGrid(cols: 2, rows: 1), step: 0, totalSteps: 5, settled: false, slot: 0)
        let second = RenderFrame(specID: "E90", grid: ColorGrid(cols: 2, rows: 1), step: 1, totalSteps: 5, settled: false, slot: 1)
        sink.deliver(first)
        sink.deliver(second)
        XCTAssertEqual(sink.deliveredCount, 2)
        XCTAssertEqual(sink.mostRecent?.step, 1)
        XCTAssertFalse(sink.isFinished)

        let waited = sink.waitForFrame(timeout: 0.01)
        XCTAssertEqual(waited?.step, 1)

        sink.finish()
        XCTAssertTrue(sink.isFinished)
    }

    func testReadbackSinkTimesOutWithNoFrame() {
        let sink = ReadbackSink()
        XCTAssertNil(sink.waitForFrame(timeout: 0.01))
    }

    func testSinkFactoryBuildsReadbackOnly() throws {
        XCTAssertTrue(try SinkFactory.make(.readback) is ReadbackSink)
        XCTAssertThrowsError(try SinkFactory.make(.layer))
        XCTAssertThrowsError(try SinkFactory.make(.led))
    }

    func testManualClockDeliversDeltasUntilStopped() {
        let clock = ManualClock()
        let box = DeltaBox()
        clock.start { box.deltas.append($0) }
        clock.pump(1.0 / 30)
        clock.pump(2.0 / 30)
        clock.stop()
        clock.pump(3.0 / 30)
        XCTAssertEqual(box.deltas.count, 2)
        XCTAssertEqual(box.deltas[1], 2.0 / 30, accuracy: 1e-9)
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

    /// `drive` starts a clock on the render thread and advances the run on each
    /// tick. The manual clock lets the test pump ticks and wait for frames.
    func testDriveAdvancesOnEachClockTick() async throws {
        guard GPUContext.isAvailable else {
            throw XCTSkip("no Metal 4 device")
        }
        let spec = Catalog.spec(id: "E30")!
        let sink = ReadbackSink()
        let clock = ManualClock()
        let actor = RenderActor()
        try await actor.configure(spec: spec, cols: 20, rows: 10, steps: 40, sink: sink)
        XCTAssertEqual(sink.deliveredCount, 1)
        _ = sink.waitForFrame(timeout: 0.01) // consume the seed frame's signal
        await actor.drive(clock: clock, stepsPerFrame: 5)

        clock.pump(1.0 / 30)
        let advanced = sink.waitForFrame(timeout: 0.5)
        XCTAssertEqual(advanced?.step, 5)
        XCTAssertEqual(sink.deliveredCount, 2)
        let error = await actor.lastError
        XCTAssertNil(error)

        await actor.stopDriving(clock: clock)
        await actor.shutdown()
    }

    /// The GPU incremental path must match `IncrementalRenderer` frame for
    /// frame, including the partially filled grid while the run is in progress.
    func testRenderActorMatchesIncrementalCPU() async throws {
        guard GPUContext.isAvailable else {
            throw XCTSkip("no Metal 4 device")
        }
        let spec = Catalog.spec(id: "E90")!
        let cols = 80
        let rows = 40
        let steps = 120
        let sink = ReadbackSink()
        let actor = RenderActor()

        let cpu = IncrementalRenderer(spec: spec, cols: cols, rows: rows, steps: steps)
        let seed = try await actor.configure(spec: spec, cols: cols, rows: rows, steps: steps, sink: sink)
        XCTAssertEqual(seed.grid, cpu.colorGrid)
        XCTAssertEqual(seed.step, 0)
        XCTAssertEqual(seed.slot, 0)

        var delivered = 1
        while !cpu.settled {
            let settled = cpu.advance(by: 7)
            let frame = try await actor.advance(by: 7)
            XCTAssertEqual(frame?.grid, cpu.colorGrid, "step \(cpu.step)")
            XCTAssertEqual(frame?.settled, settled)
            delivered += 1
        }
        XCTAssertGreaterThan(delivered, 1)

        // The run settles on the last source row and the sink saw every frame.
        let last = sink.mostRecent
        XCTAssertEqual(last?.step, steps - 1)
        XCTAssertTrue(last?.settled == true)
        XCTAssertEqual(sink.deliveredCount, delivered)

        // reset() returns to the seed frame.
        let reseeded = try await actor.reset()
        XCTAssertEqual(reseeded?.step, 0)
        XCTAssertFalse(reseeded?.settled == true)

        await actor.shutdown()
        XCTAssertTrue(sink.isFinished)
    }

    /// `MetalSimulation.reset()` returns to the seed frame and reproduces it.
    func testMetalSimulationResetReproducesSeed() throws {
        guard GPUContext.isAvailable else {
            throw XCTSkip("no Metal 4 device")
        }
        let spec = Catalog.spec(id: "T1329")!
        let context = try GPUContext()
        let simulation = try MetalSimulation(spec: spec, cols: 61, rows: 40, steps: 100, context: context)
        let seed = try simulation.render(chunk: 0)
        try simulation.render(chunk: 100)
        simulation.reset()
        XCTAssertEqual(simulation.step, 0)
        XCTAssertEqual(try simulation.render(chunk: 0), seed)
    }
}
