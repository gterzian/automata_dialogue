/// Owns delivery of a finished GPU-resident frame. The simulation core is
/// sink-independent: the same `MetalSimulation` feeds the screen and any future
/// sink. A sink is confined to the render actor, so implementations may hold
/// mutable state without locking; they are declared `Sendable` only because
/// `configure` accepts one across the actor boundary.
public protocol FrameSink: AnyObject, Sendable {
    /// Delivers a completed frame. Called on the render actor.
    func deliver(_ frame: RenderFrame)

    /// Called when the run ends or the actor shuts down.
    func finish()
}
