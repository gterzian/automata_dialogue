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

/// The stream of events a run produces, in the order the UI consumes them:
/// the model's answer text, then the chosen entry.
public enum AgentEvent: Sendable, Hashable {
    /// The model's full answer, batched by the UI. The CLI prints it as debug
    /// output, so a run that fails to parse still shows what the model said.
    case text(String)
    /// The single answer: the catalog entry the model chose.
    case choice(Choice)
    case finished
    case failed(String)
}
