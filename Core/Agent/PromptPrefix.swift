/// The part of a prompt a backend may reuse from the run before it. A prompt is
/// the system turn followed by the submission, so the reusable part is what two
/// prompts share — and only up to the first image placeholder, because an
/// image's embeddings belong to the run that encoded them.
public enum PromptPrefix {
    /// The number of leading tokens in `tokens` that a cache holding `previous`
    /// can serve.
    public static func reusableLength(
        of tokens: [Int32],
        after previous: [Int32],
        imageTokenID: Int32
    ) -> Int {
        let limit = min(tokens.count, previous.count)
        var shared = 0
        while shared < limit, tokens[shared] == previous[shared] { shared += 1 }
        guard let firstImage = tokens.firstIndex(of: imageTokenID) else { return shared }
        return min(shared, firstImage)
    }
}
