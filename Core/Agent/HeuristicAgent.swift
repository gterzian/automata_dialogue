import Foundation

/// Anything that can run one input and produce the ordered agent events. The
/// MLX `AgentEngine` and the deterministic `HeuristicAgent` both conform, so the
/// app can run with or without a model.
public protocol AgentRunning: Sendable {
    func run(_ input: AgentInput) -> AsyncThrowingStream<AgentEvent, Error>
}

/// A deterministic, model-free agent. It exercises the same `ToolDispatcher`
/// the real agent uses (so ordering and validation are shared), but derives the
/// label from the input text or a stable hash instead of a VLM. This is what
/// lets the whole app run with no weights present; the MLX engine replaces it
/// in the `Agent` target.
public struct HeuristicAgent: AgentRunning {
    public init() {}

    public func run(_ input: AgentInput) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let dispatcher = ToolDispatcher(catalog: Catalog.all) { event in
                    continuation.yield(event)
                }
                let label = Self.label(for: input)
                let ratingCall = ToolInvocation(
                    name: ToolSchemas.rateInputName,
                    arguments: [
                        "label": .string(label.rawValue),
                        "confidence": .string(RatingConfidence.high.rawValue),
                        "primitives": .string(Self.primitives(for: input)),
                        "description": .string(Self.describe(label: label)),
                        "reason": .string("Deterministic heuristic run without a model; the label is derived from the input text or a stable hash."),
                        "borderline_note": .string(""),
                    ]
                )
                _ = await dispatcher.handle(ratingCall)

                let id = Self.pickID(label: label, input: input)
                let choiceCall = ToolInvocation(
                    name: ToolSchemas.chooseAutomatonName,
                    arguments: [
                        "id": .string(id),
                        "rationale": .string("The \(label.rawValue) class matches the input's character."),
                    ]
                )
                _ = await dispatcher.handle(choiceCall)

                continuation.yield(.text("\(label.rawValue): displaying \(id)."))
                continuation.yield(.finished)
                continuation.finish()
            }
        }
    }

    // MARK: - Heuristics

    static func label(for input: AgentInput) -> RatingLabel {
        let text = input.text.lowercased()
        for label in RatingLabel.allCases where text.contains(label.rawValue) {
            return label
        }
        let seed = stableHash(input)
        // Weight toward the classes with more entries so the demo varies.
        let labels = RatingLabel.allCases
        return labels[Int(seed % UInt64(labels.count))]
    }

    static func pickID(label: RatingLabel, input: AgentInput) -> String {
        let allowed = Set(label.allowedBehaviors)
        let ids = Catalog.all.filter { allowed.contains($0.behavior) }.map(\.id)
        guard !ids.isEmpty else { return Catalog.ids[0] }
        let seed = stableHash(input) / 7
        return ids[Int(seed % UInt64(ids.count))]
    }

    private static func stableHash(_ input: AgentInput) -> UInt64 {
        var bytes = Array(input.text.utf8)
        if let path = input.imageURL?.path { bytes.append(contentsOf: path.utf8) }
        if bytes.isEmpty { bytes = [0x52, 0x41, 0x54, 0x45, 0x52] } // "RATER"
        return RowHash.fnv1a(bytes)
    }

    private static func primitives(for input: AgentInput) -> String {
        var parts: [String] = []
        if input.imageURL != nil { parts.append("one attached image") }
        if !input.text.isEmpty { parts.append("the prompt text") }
        return parts.isEmpty ? "the input" : parts.joined(separator: ", ")
    }

    private static func describe(label: RatingLabel) -> String {
        switch label {
        case .simple: "A few primitives in one obvious arrangement."
        case .structured: "A short rule generates many parts through repetition or symmetry."
        case .random: "No rule compresses the description."
        case .complex: "Simple primitives interact and recognizable structures emerge."
        }
    }
}
