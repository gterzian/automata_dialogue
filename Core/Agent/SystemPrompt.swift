import Foundation

/// Assembles the single immutable system prompt at launch: how to match (by
/// class of behavior, not by likeness), the four behavior classes, the flat
/// catalog, and the answer format. A run is one plain-text answer, so the model
/// needs the candidates up front; the catalog is embedded here rather than
/// returned by a listing call. The string is identical on every run, so it
/// stays a cacheable prefix.
public enum SystemPrompt {
    public static func build() -> String {
        [classes, automata, answer].joined(separator: "\n\n")
    }

    /// Rough token estimate at ~4 characters/token, for the budget test.
    public static func estimatedTokenCount(of text: String) -> Int {
        text.count / 4
    }

    /// The task and the four classes. The match is explicitly conceptual: the
    /// model picks the class of the image's pattern, then an automaton of that
    /// class, rather than an automaton whose *look* resembles the drawing.
    /// Keep in sync with `artifacts/System prompt_ choosing an automaton.md`.
    public static let classes = """
    You choose which cellular automaton to display for the input image.

    Do not look for an automaton that resembles the image. Match at the level of behavior: first decide which class of pattern the image shows, then choose an automaton whose behavior has that class. The image is a drawing, not a cellular automaton, so the match is conceptual, not visual. Every entry in the chosen class qualifies; pick the one whose overall character fits the image best.

    Judge the drawn shapes, not the page: paper background, dotted grids, and UI labels carry no pattern.

    ## The four classes

    - repetition: a blank or uniformly filled field; one basic shape alone; one unit repeated by translation, mirroring, or even spacing; or identical marks at irregular positions. Stripes, a row of identical marks, and a grid belong here. The picture is settled and quiet, and each mark stands on its own.
    - nesting: one shape at several different scales, so larger copies contain smaller ones. The composition is self-similar and fractal-like, such as one shape shown in three sizes. Every scale shows the same shape.
    - randomness: irregular and busy throughout. No short rule captures it, so a complete description lists every element. Small local motifs, such as triangles, dots, or short repeated blocks, may recur here and there, but nothing persists or travels to meet and interact with another structure; the whole stays unorganized.
    - complexity: several different kinds of simple parts interact, and the whole shows structures that the parts alone do not predict. It mixes order and randomness: calm regions sit beside active ones, and localized structures travel between them, so what happens in one place depends on structures that moved there from another. A glyph whose strokes interact belongs here, as does a busy composition whose parts depend on each other.

    ## How to choose

    1. Decide the class of the image's pattern from the four above.
    2. Choose an automaton below that has that class.
    3. Among those, prefer the one whose character best fits the image.

    Signals, checked in this order:
    - a blank or uniformly filled field -> repetition
    - one mark or a single plain shape alone -> repetition
    - one shape repeated, mirrored, or placed at irregular positions -> repetition
    - one shape at several scales -> nesting
    - irregular scatter with uniform busyness and no organizing idea -> randomness
    - several different kinds of shapes whose arrangement shows balance, flow, or mutual dependence -> complexity
    - a character or glyph of several interacting strokes -> complexity

    ## Two quick tests for borderline cases

    - Activity: sparse and settled points to repetition; uniformly busy points to randomness; calm regions beside active regions point to complexity.
    - Sensitivity: imagine moving one stroke. If the effect stays in that stroke's neighborhood, the class is repetition. If the effect ripples through the whole composition, the class is randomness. If it matters where structures have traveled and met, the class is complexity.
    """

    /// The flat inventory: one line per entry, `id | class | look`. The class
    /// travels with each entry instead of grouping, so the model does not have
    /// to map a separate class table onto the listing.
    public static let automata: String = {
        var lines = [
            "## Automata",
            "",
            "Each line is an id, its class, and how that automaton behaves. The description describes the automaton, not the image; use it only to choose within the class you picked.",
        ]
        lines.append(contentsOf: Catalog.promptIndexLines)
        return lines.joined(separator: "\n")
    }()

    /// The exact reply shape the parser (`ChoiceParser`) understands.
    public static let answer = """
    ## How to answer

    Reply with exactly two lines and no other text:

    id: <one id from the list>
    reason: <one sentence naming the class you matched and why it fits>
    """
}
