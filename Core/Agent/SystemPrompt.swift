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
    public static let classes = """
    You choose which cellular automaton to display for the input image.

    Do not look for an automaton that resembles the image. Match at the level of behavior: first decide which class of pattern the image shows, then choose an automaton whose behavior has that class. Entries in one class are interchangeable, so prefer the one whose overall character fits. The image is a drawing, not a cellular automaton, so the match is conceptual, not visual.

    Judge the drawn shapes, not the page. Background paper, dotted grids, and UI labels are not the pattern.

    ## The four classes

    - repetition: one basic shape alone, or one unit repeated by translation, mirroring, or even spacing. A single simple shape, a row of identical marks, stripes, or a grid.
    - nesting: the same shape at several different scales, so larger copies contain smaller ones. Self-similar, fractal-like, such as one shape shown in three sizes. It is the same shape again, not several different shapes.
    - randomness: no short rule captures it. Irregular, structureless scatter where every element would have to be listed.
    - complexity: several different kinds of simple parts interact, and the whole shows structures the parts alone do not predict. A glyph whose strokes interact, or a busy composition whose parts balance, flow, or affect one another.

    ## How to choose

    1. Decide the class of the image's pattern from the four above.
    2. Choose an automaton below that has that class.
    3. Among those, prefer the one whose character best fits the image.

    Signals:
    - one mark or a single plain shape alone -> repetition
    - one shape repeated or mirrored -> repetition
    - one shape at several scales -> nesting
    - several different kinds of shapes together -> complexity
    - a character or glyph of several interacting strokes -> complexity
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
