import Foundation

/// One submitted input: optional text plus an optional image file path (the
/// normalized 512×512 PNG from `Core/Import`).
public struct AgentInput: Sendable, Hashable {
    public var text: String
    public var imageURL: URL?

    public init(text: String, imageURL: URL? = nil) {
        self.text = text
        self.imageURL = imageURL
    }
}

/// The stream of events a run produces, in the order the UI consumes them:
/// rating card, then choice card, then the closing sentence.
public enum AgentEvent: Sendable, Hashable {
    /// Closing sentence text, batched by the UI.
    case text(String)
    /// From `rate_input`.
    case rating(Rating)
    /// From `choose_automaton`.
    case choice(Choice)
    case finished
    case failed(String)
}

/// A tool call as the dispatcher sees it. `Core` defines this instead of using
/// `mlx-swift-lm`'s `ToolCall` so the dispatcher is testable without MLX; the
/// `Agent` target converts.
public struct ToolInvocation: Sendable, Hashable {
    public var name: String
    public var arguments: [String: JSONValue]
    public var id: String?

    public init(name: String, arguments: [String: JSONValue] = [:], id: String? = nil) {
        self.name = name
        self.arguments = arguments
        self.id = id
    }

    public func string(_ key: String) -> String? {
        arguments[key]?.stringValue
    }
}
