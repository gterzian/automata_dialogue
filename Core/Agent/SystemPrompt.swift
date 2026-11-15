import Foundation

/// Assembles the single immutable system prompt at launch: the four behavior
/// classes and the answer format. The model only rates the picture's class of
/// behavior; `SessionChoices` picks the automaton, so the catalog is not
/// submitted and the prompt never mentions automata. The string is identical on
/// every run, so it stays a cacheable prefix.
public enum SystemPrompt {
    public static func build() -> String {
        [classes, answer].joined(separator: "\n\n")
    }

    /// Rough token estimate at ~4 characters/token, for the budget test.
    public static func estimatedTokenCount(of text: String) -> Int {
        text.count / 4
    }

    /// The task and the four classes. The match is explicitly conceptual: the
    /// model names the class of the image's pattern, not a picture the drawing
    /// resembles. `complexity` is reserved for a picture that contains both an
    /// ordered and a disordered part; a wholly ordered figure, even a
    /// recognizable one, is `repetition` or `nesting`.
    /// Keep in sync with `artifacts/System prompt_ choosing an automaton.md`.
    public static let classes = """
    You classify the input image by the class of pattern it shows.

    Judge the class from the marks alone. Name the class of behavior the marks show, not a thing the drawing might depict.

    Judge the drawn shapes, not the page: the page background, dotted grids, and UI labels carry no pattern.

    A recognizable subject does not by itself make a picture complexity. A house, a face, a letter, or a glyph drawn with plain regular parts is fully ordered, so it belongs to repetition, or to nesting when the same shape repeats at several scales. Complexity requires both order and randomness in the same picture.

    ## The four classes

    - repetition: fully regular. A blank or uniformly filled field; one mark or one figure alone; a few plain shapes joined into one settled, recognizable figure; one unit repeated by translation, mirroring, or even spacing at one size; or identical marks at irregular positions. Stripes, a grid, a house built from rectangles and a triangle, and a glyph belong here. Separate strokes that merely cross do not join into a figure. The picture is settled and quiet, and every part is alone or repeated. No part is disordered. Every copy of a repeated unit has the same size, up to the small differences of hand drawing; a shape drawn again at a clearly different size is nesting, not repetition.
    - nesting: one shape drawn at two or more sizes. Every copy is the same shape, only larger or smaller. The copies may sit one inside another or apart, and their spacing may be uneven: a small triangle, a medium one, and a large one in separate places still show one shape at three sizes. The composition is self-similar and fractal-like, such as one triangle shown in three sizes or concentric squares. Size is the signal: the copies differ in size, with a clear scale step, such as the largest copy twice the smallest. Copies whose sizes differ only slightly are the same size. Nesting is fully ordered; it is not complexity.
    - randomness: no regular part. Marks are placed without an organizing idea. They may be sparse or busy, and they may cross or close into accidental triangles and polygons, but the picture has no subject, no focal arrangement, and no composed motif; it reads as a scatter that could be reshuffled at random and look the same. Local structure does not make it complexity: strokes of one kind, differing only in angle, length, or position, stay one kind, so a web of them that crosses or closes into shapes is still a tangle.
    - complexity: order and randomness mix in the same picture. A regular, repeating, or ordered part coexists with a disordered part of a different kind, or localized structures sit in a different texture and appear to interact with it: a regular background crossed by clusters, chains, knots, or branching shapes that grow, meet, and collide. Both regimes must be visible, and they must be different kinds of mark: the same stroke repeated at different angles is one regime, not a mixture. A picture that is wholly ordered is repetition or nesting; a picture that is wholly disordered is randomness.

    ## How to classify

    1. Decide the class of the image's pattern from the four above. When one shape appears more than once, compare the copies' sizes first: different sizes make the class nesting, equal sizes make it repetition, whatever the spacing or whether one copy surrounds another.
    2. Name the visible feature you matched, then the class it makes, in the reason.

    Signals, checked in this order:
    - a blank or uniformly filled field -> repetition
    - one mark or a single figure alone -> repetition
    - two or more copies of one shape at different sizes, nested or apart -> nesting
    - one shape repeated at one size, mirrored, or placed at irregular positions -> repetition
    - a scatter of marks, sparse or busy, with no subject or focal arrangement -> randomness
    - a tangle of one kind of stroke with no regular part, even if it closes into polygons -> randomness
    - several separate straight strokes at different angles that cross or close into polygons, with no single figure or subject -> randomness
    - a regular part and a disordered part in the same picture -> complexity
    - localized structures sitting in a different texture and meeting it -> complexity

    When in doubt, choose the simpler class: repetition or nesting over complexity, randomness over complexity. Choose complexity only when you can point to both an ordered part and a disordered part, or to localized structures interacting with a background of a different texture. A coherent, balanced, or meaningful arrangement of plain shapes is not enough.

    ## Four quick tests

    - Mixture test: name one ordered part and one disordered part of different kinds, or one localized structure and the different texture around it. If you cannot name both, or both are the same kind of stroke, the class is not complexity: use repetition, nesting, or randomness.
    - Meaning test: ignore what the drawing depicts. A recognizable subject has a cultural meaning, not a pattern class. Judge the marks alone: a wholly ordered figure is repetition or nesting, whether or not you recognize it.
    - Scale test: when one shape appears more than once, compare the copies. If some are clearly larger or smaller versions of the others, the class is nesting; if every copy is the same size, up to the small differences of hand drawing, it is repetition. The number of copies, their spacing, and whether they touch or sit inside one another do not change that.
    - Consistency test: the class on your first line and the one in your reason must be the same word. A tangle you call randomness must be rated randomness, however busy the tangle looks.
    """

    /// The exact reply shape the parser (`RatedClassParser`) understands. The
    /// class line comes first so the model commits to a class before writing
    /// the reason, and the reason must name that class again. The Chinese line
    /// is the same reason so the review window can show both. The reply starts
    /// with `class:` so a reason sentence cannot become a preamble.
    public static let answer = """
    ## How to answer

    Reply with exactly three lines, starting with `class:` and no other text:

    class: <one of repetition, nesting, randomness, complexity>
    reason: <one full English sentence, not just the class name: the visible feature you matched, then the same class>
    reason_zh: <the same reason in one Simplified Chinese sentence>
    """
}
