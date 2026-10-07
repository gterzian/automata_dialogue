import Foundation

/// Owns pacing (design doc §6): the sink decides *how* a frame is delivered,
/// the clock decides *when* the simulation advances. A `CAMetalDisplayLink`-
/// backed clock runs the tick on the render actor's run loop, the same thread
/// that owns the Metal objects, so presentation stays off the main thread.
public protocol FrameClock: AnyObject, Sendable {
    /// Begins delivering ticks. `tick` receives the seconds elapsed since the
    /// previous tick.
    func start(_ tick: @escaping @Sendable (TimeInterval) -> Void)

    /// Stops delivering ticks. Safe to call when already stopped.
    func stop()
}
