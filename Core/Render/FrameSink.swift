import Foundation

/// Owns delivery of a finished frame. The simulation core is
/// sink-independent: the same `MetalSimulation` feeds the screen, CPU readback,
/// and the LED path through different sinks. A sink is confined to the render
/// actor, so implementations may hold mutable state without locking; they are
/// declared `Sendable` only because `configure` accepts one across the actor
/// boundary.
public protocol FrameSink: AnyObject, Sendable {
    /// Whether this sink can present a GPU-resident grid. When false (the
    /// default) the actor reads the grid back and delivers it in `RenderFrame`;
    /// when true the actor skips the readback and sets `RenderFrame.gpu`
    /// instead.
    var wantsGPUResidentFrames: Bool { get }

    /// Delivers a completed frame. Called on the render actor.
    func deliver(_ frame: RenderFrame)

    /// Called when the run ends or the actor shuts down.
    func finish()
}

public extension FrameSink {
    var wantsGPUResidentFrames: Bool { false }
}

/// A sink that retains the most recent frame for a CPU consumer and lets it
/// wait for the next one. Used by `rater-cli`-style headless drivers and by the
/// tests that compare the GPU path with `CPUAutomatonRenderer`.
public final class ReadbackSink: FrameSink, @unchecked Sendable {
    private let lock = NSLock()
    private var latest: RenderFrame?
    private var frameCount = 0
    private var finished = false
    private let available = DispatchSemaphore(value: 0)

    public init() {}

    public func deliver(_ frame: RenderFrame) {
        lock.lock()
        latest = frame
        frameCount += 1
        lock.unlock()
        available.signal()
    }

    public func finish() {
        lock.lock()
        finished = true
        lock.unlock()
        available.signal()
    }

    /// The most recent frame, if any.
    public var mostRecent: RenderFrame? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    /// Number of frames delivered so far.
    public var deliveredCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return frameCount
    }

    public var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }

    /// Blocks up to `timeout` for the next frame and returns the latest one.
    public func waitForFrame(timeout: TimeInterval = 1) -> RenderFrame? {
        _ = available.wait(timeout: .now() + timeout)
        return mostRecent
    }
}

/// The factory builds only context-free sinks, so a `LayerSink` comes from
/// `RenderActor.makeLayerSink(layer:)`, which supplies the actor's context.
public enum SinkKind: Sendable, CaseIterable {
    case readback
    case layer
    case led
}

public enum SinkFactory {
    public enum SinkError: Error, LocalizedError {
        /// The sink exists but needs a surface or context the factory cannot
        /// supply (the layer sink).
        case needsContext(SinkKind)
        /// The sink is not built yet.
        case unimplemented(SinkKind)

        public var errorDescription: String? {
            switch self {
            case .needsContext(let kind):
                "\(kind) needs a layer and context; use RenderActor.makeLayerSink(layer:)."
            case .unimplemented(let kind):
                "No sink is built for \(kind) yet."
            }
        }
    }

    public static func make(_ kind: SinkKind) throws -> any FrameSink {
        switch kind {
        case .readback: ReadbackSink()
        case .layer: throw SinkError.needsContext(kind)
        case .led: throw SinkError.unimplemented(kind)
        }
    }
}
