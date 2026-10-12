import Darwin
import Foundation
import QuartzCore

/// Owns the Metal objects for one app and confines them to a dedicated run
/// loop. The main thread configures a run, advances it, and
/// receives `RenderFrame`s through a `FrameSink`; no Metal call or `present`
/// runs on the main thread. `configure` and `advance` are synchronous on the
/// render actor, so their committed work has completed (and for the readback
/// sink, the grid is ready) before they return.
@available(macOS 26.0, *)
public actor RenderActor {
    public nonisolated let executor = RenderExecutor()

    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }

    private var context: GPUContext?
    private var simulation: MetalSimulation?
    private var sink: (any FrameSink)?
    /// Sub-row carry for `.timed` pacing, owned by the render actor so the
    /// clock's non-isolated tick can hand the delta to an isolated advance.
    private var paceRemainder = 0.0

    public init() {}

    /// Creates the GPU context on the render thread. Idempotent.
    public func start() throws {
        guard context == nil else { return }
        context = try GPUContext()
    }

    public var isStarted: Bool { context != nil }

    /// Starts a run and delivers the seed frame. A previous run is dropped.
    @discardableResult
    public func configure(
        spec: ProgramSpec,
        cols: Int,
        rows: Int,
        steps: Int? = nil,
        sink: any FrameSink
    ) throws -> RenderFrame {
        try start()
        guard let context else { throw GPUContext.GPUError.noMetal4Device }
        finishRun()
        paceRemainder = 0
        self.sink = sink
        let simulation = try MetalSimulation(spec: spec, cols: cols, rows: rows, steps: steps, context: context)
        self.simulation = simulation
        return try deliver(simulation, chunk: 0)
    }

    /// Advances up to `count` source rows and delivers the resulting frame.
    @discardableResult
    public func advance(by count: Int) throws -> RenderFrame? {
        guard let simulation else { return nil }
        return try deliver(simulation, chunk: count)
    }

    /// Advances to the last source row and delivers the settled frame.
    @discardableResult
    public func advanceToEnd() throws -> RenderFrame? {
        guard let simulation else { return nil }
        return try deliver(simulation, chunk: simulation.totalSteps - 1)
    }

    /// Returns to the seed row and delivers frame 0.
    @discardableResult
    public func reset() throws -> RenderFrame? {
        guard let simulation else { return nil }
        simulation.reset()
        return try deliver(simulation, chunk: 0)
    }

    /// Creates a `LayerSink` over `layer` using the actor's GPU context, so the
    /// sink's renderer and the simulation share one device, queue, and
    /// residency set. The GPU-resident path depends on that sharing.
    public func makeLayerSink(layer: CAMetalLayer) throws -> LayerSink {
        try start()
        guard let context else { throw GPUContext.GPUError.noMetal4Device }
        return try LayerSink(layer: layer, context: context)
    }

    /// Ends the current run and releases its sink; the GPU context stays alive.
    public func finishRun() {
        sink?.finish()
        sink = nil
        simulation = nil
    }

    /// The last error from a driven run, if any. The clock tick cannot throw,
    /// so a failed `advance` is recorded here instead of being dropped.
    public private(set) var lastError: String?

    /// Starts `clock` on the render thread and advances the run by `pacing` on
    /// each tick. Because this is actor-isolated, the display link is added to
    /// the render run loop, so ticks and presentation share the Metal thread.
    public func drive(clock: any FrameClock, pacing: RenderPacing) {
        paceRemainder = 0
        clock.start { [weak self] delta in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.tick(delta: delta, pacing: pacing)
                } catch {
                    await self.record(error)
                }
            }
        }
    }

    /// Convenience for a fixed advance per tick (the tests pump this by hand).
    public func drive(clock: any FrameClock, stepsPerFrame: Int) {
        drive(clock: clock, pacing: .fixed(stepsPerFrame))
    }

    private func tick(delta: TimeInterval, pacing: RenderPacing) throws {
        let steps = pacing.steps(for: delta, remainder: &paceRemainder)
        guard steps > 0 else { return }
        _ = try advance(by: steps)
    }

    /// Stops a clock started with `drive`.
    public func stopDriving(clock: any FrameClock) {
        clock.stop()
    }

    /// Stops the render thread. Status calls must not follow.
    public func shutdown() {
        finishRun()
        context = nil
        executor.shutdown()
    }

    private func record(_ error: Error) {
        lastError = error.localizedDescription
    }

    // MARK: - Test hooks

    /// Confirms isolated work runs off the main thread.
    func runsOffMainThread() -> Bool { !Thread.isMainThread }

    /// Identity of the render thread; two calls must agree.
    func renderThreadID() -> UInt { UInt(bitPattern: pthread_self()) }

    // MARK: - Private

    private func deliver(_ simulation: MetalSimulation, chunk: Int) throws -> RenderFrame {
        let grid: ColorGrid?
        let gpu: GPUColorGrid?
        if sink?.wantsGPUResidentFrames == true {
            gpu = try simulation.renderGPU(chunk: chunk)
            grid = nil
        } else {
            grid = try simulation.render(chunk: chunk)
            gpu = nil
        }
        let frame = RenderFrame(
            specID: simulation.spec.id,
            grid: grid,
            gpu: gpu,
            step: simulation.step,
            totalSteps: simulation.totalSteps,
            settled: simulation.step >= simulation.totalSteps - 1,
            slot: simulation.lastSlot
        )
        sink?.deliver(frame)
        return frame
    }
}
