/// The bookkeeping a batch of runs shares whichever backend produces the
/// tokens: the no-repeat window and the reading of the model's answer. A
/// backend renders the prompt and runs its model, then hands the answer back
/// here, so the dialogue behaves the same on either runtime.
public struct AgentDialogue: Sendable {
    private var history = ChoiceHistory()

    public init() {}

    /// The user turn for one submission, with the ids its answer may not use.
    /// The exclusion note rides with the input, so the system prompt stays a
    /// cacheable prefix on both backends.
    public func turn(for text: String) -> (prompt: String, excluded: Set<String>) {
        (history.userTurn(text), Set(history.excludedIDs))
    }

    /// The choice to accept from `answer`: the parsed catalog id, unless there
    /// is none or it is one of `excluded`. An accepted choice joins the window,
    /// so the next run is asked to pick a different automaton.
    public mutating func accept(_ answer: String, excluding excluded: Set<String>) -> Choice? {
        guard let choice = ChoiceParser.choice(from: answer),
              !excluded.contains(choice.id)
        else { return nil }
        history.record(choice.id)
        return choice
    }

    /// Drops the window, so the next run is not asked to avoid earlier ids.
    public mutating func reset() {
        history = ChoiceHistory()
    }
}
