import Darwin
import Foundation
import QuartzCore

/// How a run maps its history onto the display. `.single` grows one pattern
/// downward; `.twin` shares one horizon row between an upper branch growing up
/// and a lower branch growing down.
public enum RunLayout: Sendable, Equatable {
    case single
    case twin
}

/// Owns the Metal objects for one app and confines them to a dedicated run
/// loop. The main thread configures a run, drives it through a `RenderTarget`,
/// and receives `RenderFrame`s through a `FrameSink`; no Metal call or `present`
/// runs on the main thread. `configure` and `advance` are synchronous on the
/// render actor, so their committed GPU work has completed before they return.
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
    /// The target whose frame loop `drive` started.
    private var driveTarget: (any RenderTarget)?
    /// The reveal camera, applied on each tick so the zoom moves with the
    /// growth instead of in main-actor polling steps.
    private var reveal: RevealSetup?
    /// Source steps at which the pull-back has widened the window to the whole
    /// board. Past it the fit samples columns off the board and shows the page
    /// either side of the pattern, so the run ends here instead. Computed from
    /// the grid the widest zoom-out reaches, which is where the limit is hit.
    private var revealSpanLimit: Int?
    /// Where the reveal is: the pull-back plays, then the ending eats the
    /// picture back onto the horizon and closes it into its point, and the
    /// review window advances on `settled`.
    public private(set) var revealEnding: RevealEndPhase = .playing
    /// Seconds into the ending's timeline while it plays.
    private var endingTime: TimeInterval = 0
    private var endingVariation: RevealVariation?

    public init() {}

    /// Creates the GPU context on the render thread. Idempotent.
    public func start() throws {
        guard context == nil else { return }
        context = try GPUContext()
    }

    /// Starts a run and delivers the seed frame. A previous run is dropped.
    /// `board` overrides the catalog board so the review window can simulate a
    /// board much wider than the display.
    @discardableResult
    public func configure(
        spec: ProgramSpec,
        cols: Int,
        rows: Int,
        board: Board? = nil,
        layout: RunLayout = .single,
        minimumZoom: Double = 1.0,
        reveal: RevealSetup? = nil,
        sink: any FrameSink
    ) throws -> RenderFrame {
        try start()
        guard let context else { throw GPUContext.GPUError.noMetal4Device }
        finishRun()
        paceRemainder = 0
        revealEnding = .playing
        self.sink = sink
        let simulation = try MetalSimulation(
            spec: spec, cols: cols, rows: rows, context: context, board: board,
            minimumZoom: minimumZoom, twin: layout == .twin
        )
        self.simulation = simulation
        self.reveal = reveal
        self.revealSpanLimit = reveal.map { _ in
            Self.spanLimit(
                cols: cols, rows: rows, layout: layout,
                boardWidth: (board ?? spec.board).width, minimumZoom: minimumZoom)
        }
        // The seed frame is already the close-up the camera opens at, so the
        // first tick continues from it instead of jumping scale.
        if let reveal {
            simulation.setZoom(
                RevealCamera.zoom(steps: 0, branchRows: reveal.branchRows))
        }
        return try deliver(simulation, chunk: 0)
    }

    /// The steps at which the window's sampling spans `boardWidth`, measured on
    /// the floor grid. The board is ten windows wide and the floor is at most
    /// four times wider than the base grid, so the pull-back reaches the floor
    /// long before it spans the board: the floor grid is the grid it crosses on.
    private static func spanLimit(
        cols: Int, rows: Int, layout: RunLayout,
        boardWidth: Int, minimumZoom: Double
    ) -> Int {
        let floor = min(max(minimumZoom, ViewportGeometry.minimumZoomLimit), 1)
        let floorCols = ViewportGeometry.zoomedColumns(baseCols: cols, zoom: floor)
        let floorRows = layout == .twin
            ? ViewportGeometry.twinRows(baseRows: rows, zoom: floor)
            : ViewportGeometry.zoomedRows(baseRows: rows, zoom: floor)
        let span = layout == .twin
            ? ViewportGeometry.twinHalfRows(rows: floorRows)
            : max(1, floorRows - 1)
        return ViewportGeometry.stepsThatSpanBoard(
            boardWidth: boardWidth, cols: floorCols, span: span)
    }

    /// Source rows the run has computed.
    public var steppedRows: Int { simulation?.steppedRows ?? 0 }

    /// Advances up to `count` source rows and delivers the resulting frame.
    @discardableResult
    public func advance(by count: Int) throws -> RenderFrame? {
        guard let simulation else { return nil }
        return try deliver(simulation, chunk: count)
    }

    /// Shifts the window `delta` board columns and delivers the re-fitted
    /// frame. A no-op when nothing is configured; a failed re-fit is recorded
    /// in `lastError`.
    public func pan(by delta: Int) {
        guard let simulation else { return }
        simulation.pan(by: delta)
        do {
            _ = try deliver(simulation, chunk: 0)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Sets the viewport's zoom and delivers the re-fitted frame. A no-op when
    /// nothing is configured; a failed re-fit is recorded in `lastError`.
    public func setZoom(_ zoom: Double) {
        guard let simulation else { return }
        simulation.setZoom(zoom)
        do {
            _ = try deliver(simulation, chunk: 0)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Restarts the live run from a fresh seed row and delivers frame 0. A
    /// `.rand` entry draws a different row; the sink and GPU buffers are kept,
    /// so nothing is recompiled or reallocated.
    public func restart() {
        guard let simulation else { return }
        do {
            try simulation.reseed(seed: UInt64.random(in: .min ... .max))
            revealEnding = .playing
            endingTime = 0
            endingVariation = nil
            // A restarted run opens where a fresh one does.
            if let reveal {
                simulation.setZoom(
                    RevealCamera.zoom(steps: 0, branchRows: reveal.branchRows))
            }
            _ = try deliver(simulation, chunk: 0)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Creates a `CellGridSink` over `target` using the actor's GPU context, so
    /// the sink's renderer and the simulation share one device, queue, and
    /// residency set.
    public func makeCellGridSink(target: any RenderTarget) throws -> CellGridSink {
        try start()
        guard let context else { throw GPUContext.GPUError.noMetal4Device }
        return try CellGridSink(target: target, context: context)
    }

    /// Ends the current run and releases its sink; the GPU context stays alive.
    public func finishRun() {
        stopDriving()
        sink?.finish()
        sink = nil
        simulation = nil
        reveal = nil
        revealSpanLimit = nil
        revealEnding = .playing
        endingVariation = nil
    }

    /// The last error from a driven run, if any. The clock tick cannot throw,
    /// so a failed `advance` is recorded here instead of being dropped.
    public private(set) var lastError: String?

    /// The pacing of the live driven run; `setPacing` changes it in flight.
    private var pacing: RenderPacing = .fixed(0)

    /// Starts `target`'s frame loop on the render thread and advances the run by
    /// `pacing` on each frame. Because this is actor-isolated, the loop is added
    /// to the render run loop, so frames and presentation share the Metal
    /// thread.
    public func drive(target: any RenderTarget, pacing: RenderPacing) {
        paceRemainder = 0
        self.pacing = pacing
        driveTarget = target
        target.start { [weak self] delta in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.tick(delta: delta)
                } catch {
                    await self.record(error)
                }
            }
        }
    }

    /// Changes the advance rate of a driven run in flight. The sub-row carry is
    /// dropped so the old rate's fraction cannot jump the new one.
    public func setPacing(_ pacing: RenderPacing) {
        paceRemainder = 0
        self.pacing = pacing
    }

    private func tick(delta: TimeInterval) throws {
        // The ending animates on the clock's delta alone; the run is frozen, so
        // it does not step and a paced run's zero-step tick still advances it.
        if endingVariation != nil {
            try advanceEnding(by: delta)
            return
        }
        var steps = pacing.steps(for: delta, remainder: &paceRemainder)
        guard steps > 0 else { return }
        if let reveal, let simulation {
            // The pull-back ends where the window's sampling spans the whole
            // board.
            if let limit = revealSpanLimit {
                let remaining = limit - simulation.steppedRows
                if remaining <= 0 {
                    beginEnding()
                    return
                }
                steps = min(steps, remaining)
            }
            // Refit without delivering: the frame the target draws is the one
            // `advance` delivers below, so a tick presents exactly once.
            let target = simulation.steppedRows + steps
            simulation.setZoom(RevealCamera.zoom(
                steps: target, branchRows: reveal.branchRows))
            _ = try advance(by: steps)
            if let limit = revealSpanLimit, simulation.steppedRows >= limit {
                beginEnding()
            }
            return
        }
        _ = try advance(by: steps)
    }

    /// Starts the ending once the pull-back spans the whole board: the picture
    /// is eaten back onto the horizon and the line closes into its point. The
    /// last frame it delivered is the widest view, so the fit never samples past
    /// the board's edge.
    private func beginEnding() {
        guard revealEnding == .playing else { return }
        revealEnding = .collapsing
        endingTime = 0
        endingVariation = .seeded(UInt64.random(in: .min ... .max))
    }

    /// Draws one frame of the ending, frozen on the run's last grid, and settles
    /// once the point has held for its rest beat.
    private func advanceEnding(by delta: TimeInterval) throws {
        guard let simulation, let variation = endingVariation else { return }
        endingTime += delta
        let frame = RevealTimeline.frame(
            time: Float(endingTime), rows: simulation.rows, cols: simulation.cols,
            variation: variation)
        _ = try deliver(simulation, chunk: 0, mask: frame.mask)
        guard frame.resting else { return }
        revealEnding = .settled
        stopDriving()
    }

    /// Stops the frame loop `drive` started.
    public func stopDriving() {
        driveTarget?.stop()
        driveTarget = nil
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

    private func deliver(
        _ simulation: MetalSimulation, chunk: Int, mask: RevealMask = .full
    ) throws -> RenderFrame {
        let gpu = try simulation.renderGPU(chunk: chunk)
        let frame = RenderFrame(specID: simulation.spec.id, gpu: gpu, mask: mask)
        sink?.deliver(frame)
        return frame
    }
}
