import Foundation

/// One submitted input: optional text plus an optional image file path (the
/// normalized 512×512 PNG from `Core/Import`). The engine owns the recent-choice
/// window and appends it to this turn (see `ChoiceHistory`).
public struct AgentInput: Sendable, Hashable {
    public var text: String
    public var imageURL: URL?

    public init(text: String, imageURL: URL? = nil) {
        self.text = text
        self.imageURL = imageURL
    }
}

/// Timing and token counts for one generation pass, read from the model's
/// completion info. The prompt figures are the prefill cost for this pass;
/// with the system prompt submitted on every run, they dominate a short answer.
public struct GenerationMetrics: Sendable, Hashable {
    /// Prompt tokens actually prefilled this pass.
    public let promptTokenCount: Int
    /// Prompt tokens served by a reused KV-cache prefix, or 0 when the whole
    /// prompt was prefilled.
    public let cachedPromptTokenCount: Int
    /// Tokens generated this pass.
    public let generationTokenCount: Int
    /// Seconds spent prefilling the prompt.
    public let promptTime: TimeInterval
    /// Seconds spent generating tokens.
    public let generationTime: TimeInterval

    public init(
        promptTokenCount: Int,
        cachedPromptTokenCount: Int = 0,
        generationTokenCount: Int,
        promptTime: TimeInterval,
        generationTime: TimeInterval
    ) {
        self.promptTokenCount = promptTokenCount
        self.cachedPromptTokenCount = cachedPromptTokenCount
        self.generationTokenCount = generationTokenCount
        self.promptTime = promptTime
        self.generationTime = generationTime
    }
}

/// The stream of events a run produces, in the order the UI consumes them:
/// the model's answer text, then one metrics event per generation pass, then
/// the chosen entry.
public enum AgentEvent: Sendable, Hashable {
    /// The model's full answer, batched by the UI. The CLI prints it as debug
    /// output, so a run that fails to parse still shows what the model said.
    case text(String)
    /// One generation pass's token counts and times.
    case metrics(GenerationMetrics)
    /// The single answer: the catalog entry the model chose.
    case choice(Choice)
    case finished
    case failed(String)
}
