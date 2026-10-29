/// Which runtime produces the tokens. The backends load different model
/// formats — an MLX snapshot for `mlx`, an exported Core AI bundle for
/// `coreAI` — so a run names one, and `rater-cli bench` times the same
/// reference images on each.
public enum AgentBackend: String, Sendable, Hashable, CaseIterable {
    case mlx
    case coreAI = "coreai"

    /// Reads a `--engine` argument. Case-insensitive, so `coreai` and `coreAI`
    /// name the same backend.
    public init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }

    /// The name the CLI prints, so a benchmark run records which runtime it
    /// timed.
    public var displayName: String {
        switch self {
        case .mlx: "MLX"
        case .coreAI: "Core AI"
        }
    }
}
