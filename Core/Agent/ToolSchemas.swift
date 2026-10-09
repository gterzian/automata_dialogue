import Foundation

/// The three tool declarations, built as `[String: any Sendable]` values that
/// match `mlx-swift-lm`'s `ToolSpec` shape. The catalog is **not** embedded in
/// any schema: the model learns the allowed ids from the `list_automata` tool
/// result, so the per-session token cost stays flat as the catalog grows.
public enum ToolSchemas {
    public static let rateInputName = "rate_input"
    public static let listAutomataName = "list_automata"
    public static let chooseAutomatonName = "choose_automaton"

    public static var all: [[String: any Sendable]] {
        [rateInput, listAutomata, chooseAutomaton]
    }

    public static var rateInput: [String: any Sendable] {
        let properties: [String: any Sendable] = [
            "label": field("string", description: nil, enumValues: RatingLabel.allCases.map(\.rawValue)),
            "confidence": field("string", description: nil, enumValues: RatingConfidence.allCases.map(\.rawValue)),
            "primitives": field("string", description: "The elements counted.", enumValues: nil),
            "description": field("string", description: "The one-sentence description, the generating rule, or the list of interacting structures.", enumValues: nil),
            "reason": field("string", description: "Two to four sentences on why this label fits.", enumValues: nil),
            "borderline_note": field("string", description: "Neighboring label and the feature that pulls toward it. Empty when the rating is clear.", enumValues: nil),
        ]
        return function(
            name: rateInputName,
            description: "Rate the current input. Call this first for every input.",
            properties: properties,
            required: ["label", "confidence", "primitives", "description", "reason"]
        )
    }

    public static var listAutomata: [String: any Sendable] {
        function(
            name: listAutomataName,
            description: "List the automata available for the label you just recorded. Call this second.",
            properties: [:],
            required: []
        )
    }

    public static var chooseAutomaton: [String: any Sendable] {
        let properties: [String: any Sendable] = [
            "id": field("string", description: "An id from the list_automata result.", enumValues: nil),
            "rationale": field("string", description: "One sentence linking the entry's look to the input.", enumValues: nil),
        ]
        return function(
            name: chooseAutomatonName,
            description: "Pick the inventory entry to display. Call this third, after list_automata.",
            properties: properties,
            required: ["id", "rationale"]
        )
    }

    // MARK: - Building blocks

    private static func field(
        _ type: String,
        description: String?,
        enumValues: [String]?
    ) -> [String: any Sendable] {
        var value: [String: any Sendable] = ["type": type]
        if let description { value["description"] = description }
        if let enumValues { value["enum"] = enumValues }
        return value
    }

    private static func function(
        name: String,
        description: String,
        properties: [String: any Sendable],
        required: [String]
    ) -> [String: any Sendable] {
        let parameters: [String: any Sendable] = [
            "type": "object",
            "properties": properties,
            "required": required,
        ]
        let function: [String: any Sendable] = [
            "name": name,
            "description": description,
            "parameters": parameters,
        ]
        return [
            "type": "function",
            "function": function,
        ]
    }
}
