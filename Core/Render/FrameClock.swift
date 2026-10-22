import Foundation

/// Owns pacing: the target decides *where* a frame is delivered, the clock
/// decides *when* the simulation advances. A `CAMetalDisplayLink`-backed clock
/// runs the tick on the render actor's run loop, the same thread that owns the
/// Metal objects, so presentation stays off the main thread.
public protocol FrameClock: AnyObject, Sendable {
    /// Begins delivering ticks. `tick` receives the seconds elapsed since the
    /// previous tick.
    func start(_ tick: @escaping @Sendable (TimeInterval) -> Void)

    /// Stops delivering ticks. Safe to call when already stopped.
    func stop()
}

/// How `drive` turns clock ticks into source-row advances (render ahead, paced
/// by the display link's elapsed time). `.fixed` keeps the
/// deterministic per-tick advance the tests pump by hand; `.timed` follows the
/// real tick delta so the run looks the same on a 60 Hz and a 120 Hz display.
public struct RenderPacing: Sendable, Equatable {
    private enum Mode: Equatable {
        case fixed(Int)
        case timed(stepsPerSecond: Double, maxStepsPerTick: Int)
    }

    private let mode: Mode

    /// A fixed number of source rows per tick, independent of elapsed time.
    public static func fixed(_ stepsPerFrame: Int) -> RenderPacing {
        RenderPacing(mode: .fixed(max(0, stepsPerFrame)))
    }

    /// `stepsPerSecond` source rows per second of tick time. The sub-row
    /// remainder carries to the next tick, and the accumulator is clamped to
    /// `maxStepsPerTick`, so a stalled clock advances one capped tick instead of
    /// building a backlog that would run the whole board in one frame.
    public static func timed(stepsPerSecond: Double, maxStepsPerTick: Int = 64) -> RenderPacing {
        RenderPacing(mode: .timed(stepsPerSecond: stepsPerSecond, maxStepsPerTick: max(1, maxStepsPerTick)))
    }

    /// Rows to advance for a tick of `delta` seconds. `remainder` carries the
    /// sub-row fraction between `.timed` ticks; callers reset it when a run
    /// starts.
    func steps(for delta: TimeInterval, remainder: inout Double) -> Int {
        switch mode {
        case .fixed(let stepsPerFrame):
            return stepsPerFrame
        case .timed(let stepsPerSecond, let maxStepsPerTick):
            remainder = min(remainder + delta * stepsPerSecond, Double(maxStepsPerTick))
            let steps = Int(remainder)
            remainder -= Double(steps)
            return steps
        }
    }
}
