import Foundation

/// One row in the transcript. Stable `id`s let the table distinguish an
/// in-place reconfigure from a new row insert.
public struct TranscriptEntry: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public var kind: TranscriptEntryKind

    public init(id: String, kind: TranscriptEntryKind) {
        self.id = id
        self.kind = kind
    }
}

/// The row kinds (design doc §5.2, adapted: no separate tool-call card model —
/// rating and choice are first-class cards).
public enum TranscriptEntryKind: Hashable, Sendable, Codable {
    case userInput(text: String, imagePath: String?)
    case rating(Rating)
    case choice(Choice)
    case assistantMessage(text: String, isStreaming: Bool)
    case errorMessage(String)

    public var isStreaming: Bool {
        if case .assistantMessage(_, let streaming) = self { return streaming }
        return false
    }
}

public extension TranscriptEntry {
    /// Everything a search could match, joined with newlines.
    var searchableText: String {
        switch kind {
        case .userInput(let text, _):
            return text
        case .rating(let rating):
            return [rating.label.rawValue, rating.primitives, rating.description, rating.reason, rating.borderlineNote]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        case .choice(let choice):
            return [choice.id, choice.rationale].joined(separator: "\n")
        case .assistantMessage(let text, _):
            return text
        case .errorMessage(let text):
            return text
        }
    }
}
