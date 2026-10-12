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

/// A `FrameSink` that asks the actor for GPU-resident frames and records them,
/// so a test can assert the CPU readback is skipped.
private final class GPUSink: FrameSink, @unchecked Sendable {
    let wantsGPUResidentFrames = true
    private let lock = NSLock()
    private var recorded: [RenderFrame] = []

    func deliver(_ frame: RenderFrame) {
        lock.lock()
        recorded.append(frame)
        lock.unlock()
    }

    func finish() {}

    var frames: [RenderFrame] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
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

    /// `.timed` pacing advances by the tick delta, not a fixed count.
    func testDriveTimedPacingFollowsDelta() async throws {
        guard GPUContext.isAvailable else {
            throw XCTSkip("no Metal 4 device")
        }
        let spec = Catalog.spec(id: "E30")!
        let sink = ReadbackSink()
        let clock = ManualClock()
        let actor = RenderActor()
        try await actor.configure(spec: spec, cols: 20, rows: 10, steps: 200, sink: sink)
        _ = sink.waitForFrame(timeout: 0.01) // consume the seed frame's signal
        await actor.drive(clock: clock, pacing: .timed(stepsPerSecond: 30))

        clock.pump(0.5) // 15 rows at 30 rows/s
        XCTAssertEqual(sink.waitForFrame(timeout: 0.5)?.step, 15)
        clock.pump(1.0 / 30) // one more
        XCTAssertEqual(sink.waitForFrame(timeout: 0.5)?.step, 16)

        await actor.stopDriving(clock: clock)
        await actor.shutdown()
    }

    /// `setPacing` changes the rate of a driven run in flight, so the arrows
    /// can speed the growth up or slow it down mid-run.
    func testSetPacingChangesTheRate() async throws {
        guard GPUContext.isAvailable else {
            throw XCTSkip("no Metal 4 device")
        }
        let spec = Catalog.spec(id: "E30")!
        let sink = ReadbackSink()
        let clock = ManualClock()
        let actor = RenderActor()
        try await actor.configure(spec: spec, cols: 20, rows: 10, steps: 400, sink: sink)
        _ = sink.waitForFrame(timeout: 0.01) // consume the seed frame's signal
        await actor.drive(clock: clock, pacing: .timed(stepsPerSecond: 30))

        clock.pump(1.0) // 30 rows
        XCTAssertEqual(sink.waitForFrame(timeout: 0.5)?.step, 30)

        await actor.setPacing(.timed(stepsPerSecond: 10))
        clock.pump(1.0) // 10 more rows, not another 30
        XCTAssertEqual(sink.waitForFrame(timeout: 0.5)?.step, 40)

        await actor.stopDriving(clock: clock)
        await actor.shutdown()
    }

    /// A GPU-resident sink gets the simulation's buffer and no CPU grid, and
    /// the new-row range advances monotonically across frames.
    func testGPUSinkReceivesResidentFrames() async throws {
        guard GPUContext.isAvailable else {
            throw XCTSkip("no Metal 4 device")
        }
        let spec = Catalog.spec(id: "E30")!
        let sink = GPUSink()
        let actor = RenderActor()
        let seed = try await actor.configure(spec: spec, cols: 20, rows: 10, steps: 40, sink: sink)
        XCTAssertNil(seed.grid)
        let seedGPU = try XCTUnwrap(seed.gpu)
        XCTAssertEqual(seedGPU.firstRow, 0)
        XCTAssertTrue(seedGPU.startsRun)
        XCTAssertEqual(seedGPU.cols, 20)
        XCTAssertEqual(seedGPU.rows, 10)

        let secondFrame = try await actor.advance(by: 5)
        let second = try XCTUnwrap(secondFrame)
        XCTAssertNil(second.grid)
        let secondGPU = try XCTUnwrap(second.gpu)
        XCTAssertEqual(secondGPU.firstRow, seedGPU.rowCount)
        XCTAssertFalse(secondGPU.startsRun)
        XCTAssertEqual(sink.frames.count, 2)

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

    /// A scrolling run refits the whole window each frame; the GPU path must
    /// match `IncrementalRenderer(scrolling:)` frame for frame.
    func testScrollingGPUMatchesIncrementalCPU() async throws {
        guard GPUContext.isAvailable else {
            throw XCTSkip("no Metal 4 device")
        }
        let spec = Catalog.spec(id: "E90")!
        let cols = 120
        let rows = 30
        let sink = ReadbackSink()
        let actor = RenderActor()

        let cpu = IncrementalRenderer(spec: spec, cols: cols, rows: rows, scrolling: true)
        let seed = try await actor.configure(spec: spec, cols: cols, rows: rows, scrolling: true, sink: sink)
        XCTAssertEqual(seed.grid, cpu.colorGrid)

        // Cross the fill point and keep scrolling: every frame's window must
        // agree, including the partially-filled grid before it fills.
        for _ in 0..<12 {
            _ = cpu.advance(by: 7)
            let frame = try await actor.advance(by: 7)
            XCTAssertEqual(frame?.grid, cpu.colorGrid, "step \(cpu.step)")
        }
        await actor.shutdown()
    }

    /// A scrolling GPU-resident frame always carries the full window (row 0),
    /// so the sink recompacts every row instead of accumulating.
    func testScrollingGPUSinkGetsFullWindowFrames() async throws {
        guard GPUContext.isAvailable else {
            throw XCTSkip("no Metal 4 device")
        }
        let spec = Catalog.spec(id: "E30")!
        let sink = GPUSink()
        let actor = RenderActor()
        _ = try await actor.configure(spec: spec, cols: 20, rows: 10, scrolling: true, sink: sink)
        _ = try await actor.advance(by: 25)
        for frame in sink.frames {
            let gpu = try XCTUnwrap(frame.gpu)
            XCTAssertEqual(gpu.firstRow, 0)
            XCTAssertEqual(gpu.rowCount, 10)
            XCTAssertTrue(gpu.startsRun)
        }
        await actor.shutdown()
    }

    /// A pannable `.window` frame must match `IncrementalRenderer` with the
    /// same mapping, and a pan must move both the same way.
    func testWindowMappingGPUMatchesIncrementalCPU() async throws {
        guard GPUContext.isAvailable else {
            throw XCTSkip("no Metal 4 device")
        }
        let spec = Catalog.spec(id: "E90")!
        let cols = 120
        let rows = 30
        // A board ten windows wide, as the panel simulates.
        let board = Board(width: 1200, height: spec.board.height, start: .center)
        let sink = ReadbackSink()
        let actor = RenderActor()

        let cpu = IncrementalRenderer(
            spec: spec, cols: cols, rows: rows, scrolling: true, mapping: .window, board: board)
        let seed = try await actor.configure(
            spec: spec, cols: cols, rows: rows, scrolling: true, mapping: .window, board: board, sink: sink)
        XCTAssertEqual(seed.grid, cpu.colorGrid)

        for _ in 0..<12 {
            _ = cpu.advance(by: 7)
            let frame = try await actor.advance(by: 7)
            XCTAssertEqual(frame?.grid, cpu.colorGrid, "step \(cpu.step)")
        }

        // Pan far enough to leave the first window; the two must stay in step.
        let start = cpu.viewportOrigin
        cpu.pan(by: 300)
        await actor.pan(by: 300)
        XCTAssertEqual(cpu.viewportOrigin, start + 300)
        XCTAssertEqual(sink.mostRecent?.grid, cpu.colorGrid, "after pan")
        await actor.shutdown()
    }

    /// `restart()` returns to frame 0 and, for a `.rand` entry, draws a new
    /// seed row.
    func testRestartReseedsTheRun() async throws {
        guard GPUContext.isAvailable else {
            throw XCTSkip("no Metal 4 device")
        }
        let spec = Catalog.spec(id: "E90.rand")!
        let sink = ReadbackSink()
        let actor = RenderActor()
        let first = try await actor.configure(
            spec: spec, cols: 80, rows: 20, scrolling: true, mapping: .window, sink: sink)
        for _ in 0..<5 {
            _ = try await actor.advance(by: 7)
        }
        XCTAssertGreaterThan(sink.mostRecent?.step ?? 0, 0)

        await actor.restart()
        XCTAssertEqual(sink.mostRecent?.step, 0)
        // A fresh random seed means a different first frame.
        XCTAssertNotEqual(sink.mostRecent?.grid, first.grid)
        await actor.shutdown()
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
