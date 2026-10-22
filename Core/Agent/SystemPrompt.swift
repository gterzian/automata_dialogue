import Foundation

/// Assembles the single immutable system prompt at launch: how to match (by
/// class of behavior, not by likeness), the four behavior classes, the
/// catalog grouped by class, and the answer format. A run is one plain-text
/// answer, so the model needs the candidates up front; the catalog is embedded
/// here rather than returned by a listing call. The string is identical on
/// every run, so it stays a cacheable prefix.
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

    Do not look for an automaton that resembles the image. Match at the level of behavior: first decide which class of pattern the image shows, then choose an automaton whose behavior has that class. The image is a drawing, not a cellular automaton, so the match is conceptual, not visual. Every entry in the chosen class qualifies; pick the one whose overall character fits the image best. The class heading above your id must be the class on your first line; the answer is wrong when those differ.

    Judge the drawn shapes, not the page: paper background, dotted grids, and UI labels carry no pattern.

    A recognizable subject does not by itself make a picture complexity. A house, a face, a letter, or a glyph drawn with plain regular parts is fully ordered, so it belongs to repetition, or to nesting when the same shape repeats at several scales. Complexity requires both order and randomness in the same picture.

    ## The four classes

    - repetition: fully regular. A blank or uniformly filled field; one mark or one figure alone; a few plain shapes joined into one settled, recognizable figure; one unit repeated by translation, mirroring, or even spacing; or identical marks at irregular positions. Stripes, a grid, a house built from rectangles and a triangle, and a glyph belong here. Separate strokes that merely cross do not join into a figure. The picture is settled and quiet, and every part is alone or repeated. No part is disordered.
    - nesting: one shape at several different scales, so larger copies contain smaller ones. The composition is self-similar and fractal-like, such as one shape shown in three sizes. Every scale shows the same shape. Nesting is fully ordered; it is not complexity.
    - randomness: no regular part. Marks are placed without an organizing idea. They may be sparse or busy, and they may cross or close into accidental triangles and polygons, but the picture has no subject, no focal arrangement, and no composed motif; it reads as a scatter that could be reshuffled at random and look the same. Local structure does not make it complexity: strokes of one kind, differing only in angle, length, or position, stay one kind, so a web of them that crosses or closes into shapes is still a tangle.
    - complexity: order and randomness mix in the same picture. A regular, repeating, or ordered part coexists with a disordered part of a different kind, or localized structures sit in a different texture and appear to interact with it: a regular background crossed by clusters, chains, knots, or branching shapes that grow, meet, and collide. Both regimes must be visible, and they must be different kinds of mark: the same stroke repeated at different angles is one regime, not a mixture. A picture that is wholly ordered is repetition or nesting; a picture that is wholly disordered is randomness.

    ## How to choose

    1. Decide the class of the image's pattern from the four above.
    2. Choose an id from that class's section below.
    3. Among those, prefer the one whose character best fits the image.
    4. Check that the heading above your id is the class on your first line.

    Signals, checked in this order:
    - a blank or uniformly filled field -> repetition
    - one mark or a single figure alone -> repetition
    - one shape repeated, mirrored, or placed at irregular positions -> repetition
    - one shape at several scales -> nesting
    - a scatter of marks, sparse or busy, with no subject or focal arrangement -> randomness
    - a tangle of one kind of stroke with no regular part, even if it closes into polygons -> randomness
    - several separate straight strokes at different angles that cross or close into polygons, with no single figure or subject -> randomness
    - a regular part and a disordered part in the same picture -> complexity
    - localized structures sitting in a different texture and meeting it -> complexity

    When in doubt, choose the simpler class: repetition or nesting over complexity, randomness over complexity. Choose complexity only when you can point to both an ordered part and a disordered part, or to localized structures interacting with a background of a different texture. A coherent, balanced, or meaningful arrangement of plain shapes is not enough.

    ## Three quick tests

    - Mixture test: name one ordered part and one disordered part of different kinds, or one localized structure and the different texture around it. If you cannot name both, or both are the same kind of stroke, the class is not complexity: use repetition, nesting, or randomness.
    - Meaning test: ignore what the drawing depicts. A recognizable subject has a cultural meaning, not a pattern class. Judge the marks alone: a wholly ordered figure is repetition (or nesting), whether or not you recognize it.
    - Consistency test: the heading above your id must be the same word as the class on your first line and in your reason. A tangle you call randomness needs an id under the randomness heading, however busy the tangle looks.
    """

    /// The automata listing, grouped by class. The class is a heading above
    /// its ids, so the model chooses within the class it decided instead of
    /// reading a class column at the end of each line.
    public static let automata: String = {
        var lines = [
            "## Automata",
            "",
            "Each class is a heading followed by its ids. Pick an id from the section for the class you chose; every id in that section qualifies.",
        ]
        lines.append(contentsOf: Catalog.promptIndexLines)
        return lines.joined(separator: "\n")
    }()

    /// The exact reply shape the parser (`ChoiceParser`) understands. The
    /// class line comes first so the model commits to a class before choosing
    /// an id, and the reason must name that class again. The parser reads only
    /// the id and reason lines, so the class line cannot break parsing; it is
    /// the answer's self-check. The reply starts with `class:` so a reason
    /// sentence cannot become a preamble.
    public static let answer = """
    ## How to answer

    Reply with exactly three lines, starting with `class:` and no other text:

    class: <one of repetition, nesting, randomness, complexity>
    id: <one id from the section for that class>
    reason: <one full sentence, not just the class name: the visible feature you matched, then the same class>
    """
}
