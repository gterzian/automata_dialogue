import Foundation

/// Anything that can run one input and produce the ordered agent events. The
/// MLX `AgentEngine` is the only conformer; the protocol keeps `Core`'s tests
/// and the app's `RaterModel` independent of the MLX target.
public protocol AgentRunning: Sendable {
    func run(_ input: AgentInput) -> AsyncThrowingStream<AgentEvent, Error>
}
