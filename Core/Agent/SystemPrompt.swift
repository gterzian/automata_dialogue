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
    - randomness: marks placed without an organizing idea. The marks may be sparse or busy, and they may cross or close into accidental triangles and polygons, but the picture has no subject, no focal arrangement, and no motif that is composed; it reads as a scatter that could be reshuffled at random and look the same. Local structure does not change this: strokes of one kind, differing only in angle, length, or position, stay one kind, so a web of them that crosses or closes into shapes is still a tangle.
    - complexity: the picture reads as designed or meaningful, not as a scatter. It has a visible organizing idea: a recognizable subject or symbol (a glyph, an object, a deliberate abstract composition), or several different kinds of parts that clearly respond to one another. One kind of straight stroke at different angles or lengths stays one kind; a web of such strokes is randomness even when it closes into polygons, unless it depicts a recognizable subject.

    Do not call a drawing complexity just because it looks busy or balanced. A web of straight line segments that cross or close into shapes, with no recognizable subject, is randomness.

    ## How to choose

    1. Decide the class of the image's pattern from the four above.
    2. Choose an automaton below that has that class.
    3. Among those, prefer the one whose character best fits the image.
    4. Between randomness and complexity, choose randomness unless the organizing idea is clear.

    Signals, checked in this order:
    - a blank or uniformly filled field -> repetition
    - one mark or a single plain shape alone -> repetition
    - one shape repeated, mirrored, or placed at irregular positions -> repetition
    - one shape at several scales -> nesting
    - a scatter of marks, sparse or busy, with no subject or focal arrangement -> randomness
    - a web of straight line segments that crosses or closes into shapes, with no recognizable subject -> randomness
    - several different kinds of shapes whose arrangement shows balance, flow, or mutual dependence -> complexity
    - a character or glyph of several interacting strokes -> complexity

    ## Two quick tests for borderline cases

    - Vocabulary: if the picture reads as designed or meaningful, with a subject, a focal arrangement, or a composed motif, the class is complexity. If it reads as a scatter that could be reshuffled at random without changing its character, the class is randomness.
    - Sensitivity: imagine deleting one stroke. If the picture loses nothing important, the class is randomness. If its subject, balance, or meaning would change, the class is complexity. If the effect stays in that stroke's neighborhood, the class is repetition.
    """

    /// The flat inventory: one line per entry, `id | class`. The class travels
    /// with each entry instead of grouping, so the model does not have to map a
    /// separate class table onto the listing.
    public static let automata: String = {
        var lines = [
            "## Automata",
            "",
            "Each line is an id and its class. Pick an id whose class matches the class you chose; every id of that class qualifies.",
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
