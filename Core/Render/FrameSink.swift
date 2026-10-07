import Foundation

/// Owns delivery of a finished frame (design doc §6). The simulation core is
/// sink-independent: the same `MetalSimulation` feeds the screen, CPU readback,
/// and the LED path through different sinks. A sink is confined to the render
/// actor, so implementations may hold mutable state without locking; they are
/// declared `Sendable` only because `configure` accepts one across the actor
/// boundary.
public protocol FrameSink: AnyObject, Sendable {
    /// Delivers a completed frame. Called on the render actor.
    func deliver(_ frame: RenderFrame)

    /// Called when the run ends or the actor shuts down.
    func finish()
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

/// The delivery surfaces the design lists. `.readback` is built; `.layer` and
/// `.led` arrive with `LayerSink`/`LEDSink` (see `Core/Render/README.md`).
public enum SinkKind: Sendable, CaseIterable {
    case readback
    case layer
    case led
}

public enum SinkFactory {
    public enum SinkError: Error, LocalizedError {
        case unimplemented(SinkKind)

        public var errorDescription: String? {
            switch self {
            case .unimplemented(let kind): "No sink is built for \(kind) yet."
            }
        }
    }

    public static func make(_ kind: SinkKind) throws -> any FrameSink {
        switch kind {
        case .readback: ReadbackSink()
        case .layer, .led: throw SinkError.unimplemented(kind)
        }
    }
}
