import Foundation

/// The four rating labels (rubric artifact). Raw values are the lowercase words
/// the model emits and the `rate_input` enum uses.
public enum RatingLabel: String, Sendable, Hashable, CaseIterable, Codable {
    case simple
    case structured
    case random
    case complex

    /// Behaviors whose inventory entries a label may choose from (design doc
    /// §3.5). `simple` maps to repetition; `structured` widens to nesting and
    /// repetition; `random` to randomness; `complex` to complexity.
    public var allowedBehaviors: [Behavior] {
        switch self {
        case .simple: [.repetition]
        case .structured: [.nesting, .repetition]
        case .random: [.randomness]
        case .complex: [.complexity]
        }
    }
}

public enum RatingConfidence: String, Sendable, Hashable, CaseIterable, Codable {
    case veryHigh = "very high"
    case high
    case moderate
    case low
}

/// One `rate_input` result.
public struct Rating: Sendable, Hashable, Codable {
    public var label: RatingLabel
    public var confidence: RatingConfidence
    /// The elements counted.
    public var primitives: String
    /// The one-sentence description, the generating rule, or the interacting
    /// structures.
    public var description: String
    /// Why this label fits.
    public var reason: String
    /// Neighboring label and the feature that pulls toward it; empty when the
    /// rating is clear.
    public var borderlineNote: String

    public init(
        label: RatingLabel,
        confidence: RatingConfidence,
        primitives: String,
        description: String,
        reason: String,
        borderlineNote: String = ""
    ) {
        self.label = label
        self.confidence = confidence
        self.primitives = primitives
        self.description = description
        self.reason = reason
        self.borderlineNote = borderlineNote
    }
}

/// One `choose_automaton` result.
public struct Choice: Sendable, Hashable, Codable {
    public var id: String
    public var rationale: String

    public init(id: String, rationale: String) {
        self.id = id
        self.rationale = rationale
    }
}
