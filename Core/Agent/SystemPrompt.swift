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
    /// `complexity` is reserved for a picture that contains both an ordered and
    /// a disordered part; a wholly ordered figure, even a recognizable one, is
    /// `repetition` or `nesting`.
    /// Keep in sync with `artifacts/System prompt_ choosing an automaton.md`.
    public static let classes = """
    You choose which cellular automaton to display for the input image.

    Do not look for an automaton that resembles the image. Match at the level of behavior: first decide which class of pattern the image shows, then choose an automaton whose behavior has that class. The image is a drawing, not a cellular automaton, so the match is conceptual, not visual. Every entry in the chosen class qualifies; pick the one whose overall character fits the image best.

    Judge the drawn shapes, not the page: paper background, dotted grids, and UI labels carry no pattern.

    A recognizable subject does not by itself make a picture complexity. A house, a face, a letter, or a glyph drawn with plain regular parts is fully ordered, so it belongs to repetition, or to nesting when the same shape repeats at several scales. Complexity requires both order and randomness in the same picture.

    ## The four classes

    - repetition: fully regular. A blank or uniformly filled field; one mark or one figure alone; a few plain shapes joined into one settled figure; one unit repeated by translation, mirroring, or even spacing; or identical marks at irregular positions. Stripes, a grid, a house built from rectangles and a triangle, and a glyph belong here. The picture is settled and quiet, and every part is alone or repeated. No part is disordered.
    - nesting: one shape at several different scales, so larger copies contain smaller ones. The composition is self-similar and fractal-like, such as one shape shown in three sizes. Every scale shows the same shape. Nesting is fully ordered; it is not complexity.
    - randomness: no regular part. Marks are placed without an organizing idea. They may be sparse or busy, and they may cross or close into accidental triangles and polygons, but the picture has no subject, no focal arrangement, and no composed motif; it reads as a scatter that could be reshuffled at random and look the same. Local structure does not make it complexity: strokes of one kind, differing only in angle, length, or position, stay one kind, so a web of them that crosses or closes into shapes is still a tangle.
    - complexity: order and randomness mix in the same picture. A regular, repeating, or ordered part coexists with a disordered part, or localized structures sit in a different texture and appear to interact with it: a regular background crossed by clusters, chains, knots, or branching shapes that grow, meet, and collide. Both regimes must be visible. A picture that is wholly ordered is repetition or nesting; a picture that is wholly disordered is randomness.

    ## How to choose

    1. Decide the class of the image's pattern from the four above.
    2. Choose an automaton below that has that class.
    3. Among those, prefer the one whose character best fits the image.

    Signals, checked in this order:
    - a blank or uniformly filled field -> repetition
    - one mark or a single figure alone -> repetition
    - one shape repeated, mirrored, or placed at irregular positions -> repetition
    - one shape at several scales -> nesting
    - a scatter of marks, sparse or busy, with no subject or focal arrangement -> randomness
    - a tangle of one kind of stroke with no regular part, even if it closes into polygons -> randomness
    - a regular part and a disordered part in the same picture -> complexity
    - localized structures sitting in a different texture and meeting it -> complexity

    When in doubt, choose the simpler class: repetition or nesting over complexity, randomness over complexity. Choose complexity only when you can point to both an ordered part and a disordered part, or to localized structures interacting with a background of a different texture. A coherent, balanced, or meaningful arrangement of plain shapes is not enough.

    ## Two quick tests for borderline cases

    - Mixture test: name one ordered part and one disordered part, or one localized structure and the different texture around it. If you cannot name both, the class is not complexity: use repetition, nesting, or randomness.
    - Meaning test: ignore what the drawing depicts. A recognizable subject has a cultural meaning, not a pattern class. Judge the marks alone: a wholly ordered figure is repetition (or nesting), whether or not you recognize it.
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

    /// The exact reply shape the parser (`ChoiceParser`) understands. The
    /// reason instruction leads with a complete sentence because a model that
    /// is told to "name the class" returns the bare class name; the reply
    /// starts with `id:` so a reason sentence cannot become a preamble.
    public static let answer = """
    ## How to answer

    Reply with exactly two lines, starting with `id:` and no other text:

    id: <one id from the list>
    reason: <one full sentence, not just the class name: the visible feature you matched, then the class it puts the drawing in>
    """
}
