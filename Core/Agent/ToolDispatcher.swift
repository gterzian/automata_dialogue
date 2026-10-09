import Foundation

/// Enforces the rate→list→choose order and validates arguments, one instance
/// per run. The package's validation default is `.permissive`, so schema
/// violations reach here; **every outcome is a returned string**, never a
/// throw, because a throw from the tool closure ends the stream.
///
/// An actor because the engine calls `handle` from an `@Sendable` tool-dispatch
/// closure; the actor serializes the calls a single run makes.
public actor ToolDispatcher {
    public enum Phase: Sendable, Equatable {
        case awaitingRating
        case rated(RatingLabel)
        case listed(RatingLabel)
        case done

        public var isDone: Bool { self == .done }
    }

    /// The catalog never reaches the model except through `list_automata`, so
    /// a run that loops instead of choosing is cut off here. Three calls are
    /// the happy path; the rest is retry headroom.
    public static let maxCalls = 8

    public private(set) var phase: Phase = .awaitingRating
    public private(set) var callCount = 0
    public private(set) var didFail = false
    public private(set) var rating: Rating?
    public private(set) var choice: Choice?

    private let specsByID: [String: ProgramSpec]
    private let validIDsByLabel: [RatingLabel: [String]]
    private let emit: @Sendable (AgentEvent) -> Void

    public init(
        catalog: [ProgramSpec] = Catalog.all,
        emit: @escaping @Sendable (AgentEvent) -> Void
    ) {
        var specsByID: [String: ProgramSpec] = [:]
        for spec in catalog { specsByID[spec.id] = spec }
        self.specsByID = specsByID

        var validIDsByLabel: [RatingLabel: [String]] = [:]
        for label in RatingLabel.allCases {
            let allowed = Set(label.allowedBehaviors)
            validIDsByLabel[label] = catalog
                .filter { allowed.contains($0.behavior) }
                .map(\.id)
        }
        self.validIDsByLabel = validIDsByLabel
        self.emit = emit
    }

    /// The ids a label may choose from, in catalog order.
    public func validIDs(for label: RatingLabel) -> [String] {
        validIDsByLabel[label] ?? []
    }

    public func handle(_ invocation: ToolInvocation) -> String {
        callCount += 1
        if phase != .done && callCount >= Self.maxCalls {
            didFail = true
            emit(.failed("tool call limit reached before a choice was made"))
            return "Too many tool calls. The run is finishing."
        }

        switch invocation.name {
        case ToolSchemas.rateInputName:
            return handleRate(invocation)
        case ToolSchemas.listAutomataName:
            return handleList()
        case ToolSchemas.chooseAutomatonName:
            return handleChoose(invocation)
        default:
            return "Unknown tool \(invocation.name). Call \(ToolSchemas.rateInputName) first, then \(ToolSchemas.listAutomataName), then \(ToolSchemas.chooseAutomatonName)."
        }
    }

    // MARK: - rate_input

    private func handleRate(_ invocation: ToolInvocation) -> String {
        guard case .awaitingRating = phase else {
            return "\(ToolSchemas.rateInputName) has already been recorded. Call \(ToolSchemas.listAutomataName) next."
        }

        let labels = RatingLabel.allCases.map(\.rawValue).joined(separator: ", ")
        guard let rawLabel = invocation.string("label"), let label = RatingLabel(rawValue: rawLabel) else {
            return "label must be one of \(labels). Call \(ToolSchemas.rateInputName) again."
        }

        let confidences = RatingConfidence.allCases.map(\.rawValue).joined(separator: ", ")
        guard let rawConfidence = invocation.string("confidence"),
              let confidence = RatingConfidence(rawValue: rawConfidence) else {
            return "confidence must be one of \(confidences). Call \(ToolSchemas.rateInputName) again."
        }

        for required in ["primitives", "description", "reason"] {
            guard let value = invocation.string(required), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return "\(required) is required and must not be empty. Call \(ToolSchemas.rateInputName) again."
            }
        }

        let rating = Rating(
            label: label,
            confidence: confidence,
            primitives: invocation.string("primitives") ?? "",
            description: invocation.string("description") ?? "",
            reason: invocation.string("reason") ?? "",
            borderlineNote: invocation.string("borderline_note") ?? ""
        )
        self.rating = rating
        phase = .rated(label)
        emit(.rating(rating))
        return "Rating recorded: \(label.rawValue). Call \(ToolSchemas.listAutomataName) next."
    }

    // MARK: - list_automata

    private func handleList() -> String {
        switch phase {
        case .awaitingRating:
            return "\(ToolSchemas.rateInputName) comes first. Call \(ToolSchemas.rateInputName) for this input, then \(ToolSchemas.listAutomataName)."
        case .done:
            return "\(ToolSchemas.chooseAutomatonName) has already been called."
        case .rated(let label), .listed(let label):
            phase = .listed(label)
            let ids = validIDsByLabel[label] ?? []
            var lines = [
                "Entries for \(label.rawValue) (\(ids.count)). id | title | look",
            ]
            for id in ids {
                guard let spec = specsByID[id] else { continue }
                lines.append("\(spec.id) | \(spec.title) | \(spec.look)")
            }
            lines.append("Call \(ToolSchemas.chooseAutomatonName) with one id from this list.")
            return lines.joined(separator: "\n")
        }
    }

    // MARK: - choose_automaton

    private func handleChoose(_ invocation: ToolInvocation) -> String {
        switch phase {
        case .awaitingRating:
            return "\(ToolSchemas.rateInputName) comes first. Call \(ToolSchemas.rateInputName) for this input, then \(ToolSchemas.listAutomataName)."
        case .rated(let label):
            return "Call \(ToolSchemas.listAutomataName) before choosing, to get the entries for \(label.rawValue)."
        case .done:
            return "\(ToolSchemas.chooseAutomatonName) has already been called."
        case .listed(let label):
            let valid = validIDsByLabel[label] ?? []
            guard let id = invocation.string("id"), !id.isEmpty else {
                return "id is required. Valid ids for \(label.rawValue): \(valid.joined(separator: ", "))."
            }
            guard let spec = specsByID[id] else {
                return "\(id) is not a catalog id. Valid ids for \(label.rawValue): \(valid.joined(separator: ", "))."
            }
            guard label.allowedBehaviors.contains(spec.behavior) else {
                return "\(id) is outside the classes for \(label.rawValue). Valid ids: \(valid.joined(separator: ", "))."
            }
            let choice = Choice(id: id, rationale: invocation.string("rationale") ?? "")
            self.choice = choice
            phase = .done
            emit(.choice(choice))
            return "Displaying \(id) \(spec.title)."
        }
    }
}
