import Foundation

/// The model's rating of one input: the behavior class it matched and the
/// sentence explaining the match. The automaton itself is chosen by
/// `SessionChoices`, so the model never names one.
public struct RatedClass: Sendable, Hashable, Codable {
    public var behavior: Behavior
    public var rationale: String
    /// The same reason in Simplified Chinese, shown under the English sentence
    /// in the review window. Empty when the answer omits the field.
    public var rationaleChinese: String

    public init(behavior: Behavior, rationale: String, rationaleChinese: String = "") {
        self.behavior = behavior
        self.rationale = rationale
        self.rationaleChinese = rationaleChinese
    }
}

/// The automaton displayed for one input: an entry of the rated class, picked
/// at random by `SessionChoices`, with the model's reasons for that class.
public struct Choice: Sendable, Hashable, Codable {
    public var id: String
    public var behavior: Behavior
    public var rationale: String
    public var rationaleChinese: String

    public init(
        id: String,
        behavior: Behavior,
        rationale: String,
        rationaleChinese: String = ""
    ) {
        self.id = id
        self.behavior = behavior
        self.rationale = rationale
        self.rationaleChinese = rationaleChinese
    }
}

/// The automata this session has displayed. The engine asks it for a random
/// entry of the class the model rated, so the same automaton does not come back
/// within a session. The model never sees this state: every input is rated on
/// its own and nothing is appended to the user turn.
public struct SessionChoices: Sendable, Equatable {
    private var shown: Set<String> = []

    public init() {}

    /// The ids shown so far, for diagnostics.
    public var shownIDs: Set<String> { shown }

    /// A uniformly random entry of `behavior` this session has not shown,
    /// marked as shown. When every entry of the class is already shown, the
    /// class's ids are cleared first: the class the picture matched outranks
    /// the no-repeat rule, and a session can outlast the smallest class.
    public mutating func pick(
        behavior: Behavior,
        catalog: [ProgramSpec] = Catalog.all,
        using generator: inout some RandomNumberGenerator
    ) -> ProgramSpec? {
        let entries = catalog.filter { $0.behavior == behavior }
        guard !entries.isEmpty else { return nil }
        var candidates = entries.filter { !shown.contains($0.id) }
        if candidates.isEmpty {
            shown.subtract(entries.map(\.id))
            candidates = entries
        }
        guard let picked = candidates.randomElement(using: &generator) else { return nil }
        shown.insert(picked.id)
        return picked
    }
}

/// Extracts the model's rating from its plain-text answer. The prompt
/// (`SystemPrompt`) asks for `class:`, `reason:`, and `reason_zh:` lines, but a
/// model may add prose or ignore the format, so the parser first honours an
/// explicit `class:` field and otherwise takes the first class word anywhere.
/// Pure and `nonisolated` so the MLX engine and the tests share one
/// implementation.
public enum RatedClassParser {
    public static func ratedClass(from response: String) -> RatedClass? {
        guard let behavior = classField(in: response) ?? firstClass(in: response) else {
            return nil
        }
        return RatedClass(
            behavior: behavior,
            rationale: field(named: "reason", in: response) ?? "",
            rationaleChinese: field(named: "reason_zh", in: response) ?? "")
    }

    /// The class named by a `class:` field, ignoring case and trailing
    /// punctuation. A value with extra words falls through to `firstClass`,
    /// which finds the class word inside it.
    private static func classField(in response: String) -> Behavior? {
        guard let value = field(named: "class", in: response) else { return nil }
        let name = value
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,;"))
            .lowercased()
        return Behavior(rawValue: name)
    }

    /// The text after the first `name:` at the start of a line, ignoring
    /// markdown emphasis around the name.
    private static func field(named name: String, in response: String) -> String? {
        for rawLine in response.split(separator: "\n", omittingEmptySubsequences: false) {
            // A Chinese-speaking model may use a full-width colon after the
            // field name, so both forms delimit the value.
            let line = rawLine
                .replacingOccurrences(of: "：", with: ":")
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

    /// The first class word in `text`, on word boundaries.
    private static func firstClass(in text: String) -> Behavior? {
        let haystack = text.lowercased()
        var earliest: (index: String.Index, behavior: Behavior)?
        for behavior in Behavior.allCases {
            guard let index = firstWord(behavior.rawValue, in: haystack) else { continue }
            if let earliest, index >= earliest.index { continue }
            earliest = (index, behavior)
        }
        return earliest?.behavior
    }

    private static func firstWord(_ word: String, in text: String) -> String.Index? {
        var searchStart = text.startIndex
        while let range = text.range(of: word, range: searchStart..<text.endIndex) {
            if isStartBoundary(text, at: range.lowerBound),
               isEndBoundary(text, at: range.upperBound) {
                return range.lowerBound
            }
            searchStart = range.upperBound
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
        return !(next.isLetter || next.isNumber)
    }
}
