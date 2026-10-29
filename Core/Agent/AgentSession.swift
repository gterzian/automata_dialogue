/// The lifecycle a batch of runs needs from a backend beyond `AgentRunning`.
/// The CLI holds one of these, so the review loop and the headless paths are
/// identical whichever runtime is selected; see `Agent/README.md` and
/// `AgentCoreAI/README.md` for the implementations.
public protocol AgentSession: AgentRunning {
    /// Which runtime produces the tokens.
    nonisolated var backend: AgentBackend { get }

    /// Loads the weights and whatever cache the backend keeps ahead of the
    /// first run. Best-effort: a failure leaves the first `run` to report it.
    nonisolated func prepare() async throws

    /// Drops the recent-choice window, so the next run is not asked to avoid
    /// earlier ids. `classify` uses it to score each image independently.
    nonisolated func resetHistory() async
}
