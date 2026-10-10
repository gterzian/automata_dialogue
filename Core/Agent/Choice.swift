import Foundation

/// The automaton the model chose for one input.
public struct Choice: Sendable, Hashable, Codable {
    public var id: String
    public var rationale: String

    public init(id: String, rationale: String) {
        self.id = id
        self.rationale = rationale
    }
}

/// The engine's recent-choice window, carried across runs. Before each run the
/// engine builds the user turn with `userTurn(_:)`, so the ids are submitted
/// with the image and the system prompt stays a cacheable prefix. Older choices
/// drop off once `limit` is reached.
public struct ChoiceHistory: Sendable, Equatable {
    public static let limit = 20

    private var ids: [String] = []

    public init() {}

    /// The ids not to choose this round, oldest first.
    public var excludedIDs: [String] { ids }

    public mutating func record(_ id: String) {
        ids.append(id)
        if ids.count > Self.limit { ids.removeFirst(ids.count - Self.limit) }
    }

    /// The user turn for the next submission: `text` plus a note listing the
    /// recent ids. The note lives in the user turn, not the system prompt.
    public func userTurn(_ text: String) -> String {
        guard !ids.isEmpty else { return text }
        let note = "Do not choose these ids, they were used recently: "
            + ids.joined(separator: ", ")
            + ". Choose a different automaton of the same class."
        return text.isEmpty ? note : "\(text)\n\n\(note)"
    }
}

/// Extracts the chosen automaton from the model's plain-text answer. The
/// prompt (`SystemPrompt`) asks for an `id:` line and a `reason:` line, but a
/// model may add prose or ignore the format, so the parser first honours an
/// explicit `id:` field and otherwise falls back to the first catalog id
/// mentioned anywhere. Pure and `nonisolated` so the MLX engine and the tests
/// share one implementation.
public enum ChoiceParser {
    public static func choice(
        from response: String,
        catalog: [ProgramSpec] = Catalog.all
    ) -> Choice? {
        // Longest first, so `E90.sparse` is preferred over `E90`.
        let orderedIDs = catalog.map(\.id).sorted { $0.count > $1.count }
        let idField = field(named: "id", in: response)
        guard let id = idField.flatMap({ firstID(in: $0, orderedIDs: orderedIDs) })
            ?? firstID(in: response, orderedIDs: orderedIDs)
        else { return nil }
        return Choice(id: id, rationale: field(named: "reason", in: response) ?? "")
    }

    /// The text after the first `name:` at the start of a line, ignoring
    /// markdown emphasis around the name.
    private static func field(named name: String, in response: String) -> String? {
        for rawLine in response.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine
                .replacingOccurrences(of: "*", with: "")
                .replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "->"))
                .trimmingCharacters(in: .whitespaces)
            guard let colon = line.firstIndex(of: ":") else { continue }
            guard line[..<colon].trimmingCharacters(in: .whitespaces).lowercased() == name else {
                continue
            }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : String(value)
        }
        return nil
    }

    /// The first catalog id in `text`. `.` and `-` continue an id only when a
    /// suffix follows (`E90.sparse`), so `E90.sparse` does not match as `E90`
    /// and a sentence-ending `E90.` still matches.
    private static func firstID(in text: String, orderedIDs: [String]) -> String? {
        let haystack = text.lowercased()
        for id in orderedIDs {
            let needle = id.lowercased()
            var searchStart = haystack.startIndex
            while let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
                if isStartBoundary(haystack, at: range.lowerBound),
                   isEndBoundary(haystack, at: range.upperBound) {
                    return id
                }
                searchStart = range.upperBound
            }
        }
        return nil
    }

    private static func isStartBoundary(_ text: String, at index: String.Index) -> Bool {
        guard index > text.startIndex else { return true }
        let previous = text[text.index(before: index)]
        return !(previous.isLetter || previous.isNumber)
    }

    private static func isEndBoundary(_ text: String, at index: String.Index) -> Bool {
        guard index < text.endIndex else { return true }
        let next = text[index]
        if next.isLetter || next.isNumber { return false }
        // `.` and `-` continue an id only when a suffix follows (`E90.sparse`).
        if next == "." || next == "-" {
            let suffix = text.index(after: index)
            return suffix == text.endIndex || !(text[suffix].isLetter || text[suffix].isNumber)
        }
        return true
    }
}
