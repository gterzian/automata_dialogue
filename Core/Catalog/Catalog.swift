import Foundation

/// The curated inventory as one table (design doc §4). Exactly 45 entries, in
/// the inventory's order; the dispatcher's `list_automata` listing and the CLI
/// catalog print are generated from this table.
public enum Catalog {
    public static let all: [ProgramSpec] = makeAll()

    public static let byID: [String: ProgramSpec] = {
        var map: [String: ProgramSpec] = [:]
        for spec in all { map[spec.id] = spec }
        return map
    }()

    public static var ids: [String] { all.map(\.id) }

    public static func spec(id: String) -> ProgramSpec? { byID[id] }

    /// One line per entry: `id | title | behavior | look`. The CLI catalog
    /// print uses this.
    public static var promptIndexLines: [String] {
        all.map { "\($0.id) | \($0.title) | \($0.behavior.rawValue) | \($0.look)" }
    }

    public static func count(of behavior: Behavior) -> Int {
        all.filter { $0.behavior == behavior }.count
    }

    // MARK: - Construction

    private static func defaultStepsPerSecond(height: Int) -> Double {
        // Aim for roughly a three-second run for the common heights; the
        // surface caps each tick at 64 steps so this never floods a frame.
        max(30, Double(height) / 3.0)
    }

    private static func stateCount(_ gpu: GPUProgram) -> Int {
        switch gpu {
        case .elementary: 2
        case .totalistic(_, let colors): Int(colors)
        case .k2r2: 2
        }
    }

    private static func make(
        id: String,
        title: String,
        behavior: Behavior,
        look: String,
        gpu: GPUProgram,
        board: Board,
        pinRight: Bool = false,
        stepsPerSecond: Double? = nil,
        stepLimit: Int? = nil
    ) -> ProgramSpec {
        let display = DisplayHints(
            stepsPerSecond: stepsPerSecond ?? defaultStepsPerSecond(height: board.height),
            stepLimit: stepLimit ?? board.height * 4,
            pinRight: pinRight,
            palette: Palette.standard(stateCount: stateCount(gpu))
        )
        return ProgramSpec(
            id: id,
            title: title,
            behavior: behavior,
            look: look,
            gpu: gpu,
            board: board,
            display: display,
            reference: { ProgramFactory.make(gpu: gpu, board: board) }
        )
    }

    private static func eca(
        _ id: String,
        _ rule: UInt8,
        title: String,
        behavior: Behavior,
        look: String,
        width: Int,
        height: Int,
        start: BoardStart = .center,
        pinRight: Bool = false,
        stepsPerSecond: Double? = nil,
        stepLimit: Int? = nil
    ) -> ProgramSpec {
        make(
            id: id, title: title, behavior: behavior, look: look,
            gpu: .elementary(rule: rule),
            board: Board(width: width, height: height, start: start),
            pinRight: pinRight, stepsPerSecond: stepsPerSecond, stepLimit: stepLimit
        )
    }

    private static func total(
        _ id: String,
        _ code: UInt32,
        title: String,
        behavior: Behavior,
        look: String,
        width: Int,
        height: Int,
        start: BoardStart = .center,
        stepsPerSecond: Double? = nil,
        stepLimit: Int? = nil
    ) -> ProgramSpec {
        make(
            id: id, title: title, behavior: behavior, look: look,
            gpu: .totalistic(code: code, colors: 3),
            board: Board(width: width, height: height, start: start),
            stepsPerSecond: stepsPerSecond, stepLimit: stepLimit
        )
    }

    private static func k2r2(
        _ id: String,
        _ code: UInt16,
        title: String,
        behavior: Behavior,
        look: String,
        width: Int,
        height: Int,
        start: BoardStart = .center,
        stepsPerSecond: Double? = nil,
        stepLimit: Int? = nil
    ) -> ProgramSpec {
        make(
            id: id, title: title, behavior: behavior, look: look,
            gpu: .k2r2(code: code),
            board: Board(width: width, height: height, start: start),
            stepsPerSecond: stepsPerSecond, stepLimit: stepLimit
        )
    }

    private static func makeAll() -> [ProgramSpec] {
        [
            // MARK: Repetition (9)
            eca(
                "E250", 250, title: "Rule 250", behavior: .repetition,
                look: "A single cell widens into a triangle at one cell per step, its interior a fine checkerboard that flips each step, bounded by two sharp diagonals.",
                width: 321, height: 160
            ),
            eca(
                "E109", 109, title: "Rule 109", behavior: .repetition,
                look: "A growing triangle of repeating interlocking triangle motifs over a background that alternates black and white each step, drawing horizontal stripes.",
                width: 321, height: 160
            ),
            eca(
                "E190", 190, title: "Rule 190", behavior: .repetition,
                look: "A solid black triangle expands at full speed, crossed by evenly spaced diagonal white stripes parallel to one edge.",
                width: 321, height: 160
            ),
            total(
                "T600", 600, title: "3-color totalistic 600", behavior: .repetition,
                look: "A narrow fixed-width column of stacked, textured gray triangles whose bands recur down the screen.",
                width: 161, height: 300
            ),
            total(
                "T1329", 1329, title: "3-color totalistic 1329", behavior: .repetition,
                look: "A fixed-width column of large gray-and-black triangular bands that repeats exactly every 78 steps.",
                width: 161, height: 320
            ),
            total(
                "T219", 219, title: "3-color totalistic 219", behavior: .repetition,
                look: "A triangle growing at full speed whose interior is filled with a regular comb of thin, evenly spaced vertical lines.",
                width: 321, height: 160
            ),
            total(
                "T957", 957, title: "3-color totalistic 957", behavior: .repetition,
                look: "A clean triangle filled edge to edge with a tiny regular lattice texture, like woven cloth.",
                width: 321, height: 160
            ),
            total(
                "T966", 966, title: "3-color totalistic 966", behavior: .repetition,
                look: "A triangle whose edges carry a fine lattice while the middle shows dense horizontal banding split by a vertical seam.",
                width: 321, height: 160
            ),
            total(
                "T1884", 1884, title: "3-color totalistic 1884", behavior: .repetition,
                look: "A dark-textured triangle filled with a regular arched, scale-like lattice in black and gray.",
                width: 321, height: 160
            ),
            eca(
                "E30.block1100", 30, title: "Rule 30, block 1100", behavior: .repetition,
                look: "The block black-black-white-white repeated across the row gives a pattern of period 8 with a spatial period of 4 cells.",
                width: 320, height: 160, start: .block([1, 1, 0, 0])
            ),
            k2r2(
                "K2R2-20.seed195", 20, title: "K2R2 code 20, seed 195", behavior: .repetition,
                look: "From the cells black-black-white-white-white-white-black-black a period-22 oscillator forms, 28 cells wide.",
                width: 221, height: 220, start: .seed(number: 195, colors: 2)
            ),
            total(
                "T1329.seed916", 1329, title: "3-color totalistic 1329, seed 916", behavior: .repetition,
                look: "From seed 916 a compact object of 17 to 30 cells travels across the white background.",
                width: 321, height: 300, start: .seed(number: 916, colors: 3)
            ),

            // MARK: Nesting (14)
            eca(
                "E90", 90, title: "Rule 90", behavior: .nesting,
                look: "The Sierpinski triangle: white triangular holes at every scale inside a black lace, symmetric left to right.",
                width: 401, height: 200
            ),
            eca(
                "E22", 22, title: "Rule 22", behavior: .nesting,
                look: "A symmetric nested triangle in the same family as rule 90, with slightly different detail inside the holes.",
                width: 401, height: 200
            ),
            eca(
                "E60", 60, title: "Rule 60", behavior: .nesting,
                look: "A right-angled Sierpinski triangle growing to one side, with a vertical edge on one side and a diagonal on the other.",
                width: 401, height: 200
            ),
            eca(
                "E150", 150, title: "Rule 150", behavior: .nesting,
                look: "A symmetric triangle with a busy nested structure: small branching tree-like clusters inside larger triangular voids.",
                width: 401, height: 200
            ),
            eca(
                "E105", 105, title: "Rule 105", behavior: .nesting,
                look: "The nested structure of rule 150 inverted, its fractal triangle sitting inside a background that alternates black and white each step.",
                width: 401, height: 200
            ),
            eca(
                "E129", 129, title: "Rule 129", behavior: .nesting,
                look: "A solid black screen with an inverted white Sierpinski triangle whose holes show black at every scale.",
                width: 401, height: 200
            ),
            eca(
                "E225", 225, title: "Rule 225", behavior: .nesting,
                look: "A nested pattern confined to a thin diagonal band that grows like the square root of the steps, sliding across a black field.",
                width: 401, height: 300
            ),
            total(
                "T237", 237, title: "3-color totalistic 237", behavior: .nesting,
                look: "A Sierpinski-like triangle with large white holes and fine gray detail.",
                width: 401, height: 200
            ),
            total(
                "T948", 948, title: "3-color totalistic 948", behavior: .nesting,
                look: "Nested triangles whose interiors branch into small tree-shaped motifs, a leafier fractal than T237.",
                width: 401, height: 200
            ),
            total(
                "T1749", 1749, title: "3-color totalistic 1749", behavior: .nesting,
                look: "Nested triangles with solid black triangular voids at several scales, giving more weight and contrast than the Sierpinski forms.",
                width: 401, height: 200
            ),
            total(
                "T420", 420, title: "3-color totalistic 420", behavior: .nesting,
                look: "A sparser nested triangle with large clean white regions and a branching rhythm distinct from the 2-color forms.",
                width: 401, height: 200
            ),
            eca(
                "E90.sparse", 90, title: "Rule 90, sparse random row", behavior: .nesting,
                look: "Sparse speckle at density 0.05 rebuilds itself at steps that are powers of two, so bands of thin speckle repeat at doubling intervals.",
                width: 1001, height: 200, start: .random(seed: 905, density: 0.05)
            ),
            eca(
                "E126.pairs", 126, title: "Rule 126, 2-cell blocks", behavior: .nesting,
                look: "Random black-black and white-white 2-cell blocks evolve under rule 126 like rule 90 on pairs, so the block colors reproduce rule 90 every second step.",
                width: 400, height: 200, start: .randomBlocks(seed: 126)
            ),
            eca(
                "E184.rand", 184, title: "Rule 184, random row", behavior: .nesting,
                look: "Traffic flow: black cells drift right until blocked, the black density holds at one half, and nested structure appears in the evolution.",
                width: 400, height: 200, start: .random(seed: 184, density: 0.5)
            ),

            // MARK: Randomness (10)
            eca(
                "E30", 30, title: "Rule 30", behavior: .randomness,
                look: "A clean diagonal left edge and a disordered tangle of black and white with scattered white triangles of every size; the center column is statistically random.",
                width: 401, height: 200
            ),
            eca(
                "E45", 45, title: "Rule 45", behavior: .randomness,
                look: "A regular diagonal on one side and a mix of short vertical dashes and irregular blocks filling the rest, over a horizontally striped background.",
                width: 401, height: 200
            ),
            eca(
                "E73", 73, title: "Rule 73", behavior: .randomness,
                look: "A symmetric triangle of fine, dotted, speckled texture with no long diagonals, over a horizontally striped background.",
                width: 401, height: 200
            ),
            total(
                "T177", 177, title: "3-color totalistic 177", behavior: .randomness,
                look: "A triangle whose entire interior is a gray-and-black scatter with no regular structure, bounded by clean diagonals.",
                width: 601, height: 300
            ),
            total(
                "T912", 912, title: "3-color totalistic 912", behavior: .randomness,
                look: "A mostly random interior with a visible grain of small triangles and a more regular band along the edges.",
                width: 601, height: 300
            ),
            total(
                "T2040", 2040, title: "3-color totalistic 2040", behavior: .randomness,
                look: "Random texture broken by dark triangular patches of solid black of various sizes.",
                width: 601, height: 300
            ),
            eca(
                "E90.rand", 90, title: "Rule 90, random row", behavior: .randomness,
                look: "A random field with white triangles at every size; rule 90 adds shifted copies of its single-cell triangle, so the picture carries the initial row's randomness.",
                width: 401, height: 200, start: .random(seed: 90, density: 0.5)
            ),
            eca(
                "E22.rand", 22, title: "Rule 22, random row", behavior: .randomness,
                look: "A random field with white triangles whose black density settles near 0.35, coming from the rule itself.",
                width: 401, height: 200, start: .random(seed: 22, density: 0.5)
            ),
            eca(
                "E22.seed19", 22, title: "Rule 22, seed 19", behavior: .randomness,
                look: "From the five cells 10011 the pattern grows a random core of density 0.35 that widens, with repetitive regions on both sides.",
                width: 401, height: 200, start: .seed(number: 19, colors: 2)
            ),
            eca(
                "E126.rand", 126, title: "Rule 126, random row", behavior: .randomness,
                look: "A rule that never settles: random texture at density one half with white triangles at all scales.",
                width: 301, height: 200, start: .random(seed: 1260, density: 0.5)
            ),

            // MARK: Complex localized structures (9)
            eca(
                "E110", 110, title: "Rule 110", behavior: .complexity,
                look: "From a single cell the pattern grows to one side: a regular background of small triangles with localized structures of many sizes traveling through it and colliding.",
                width: 1201, height: 400, start: .rightmost, pinRight: true
            ),
            eca(
                "E54", 54, title: "Rule 54, random start", behavior: .complexity,
                look: "From a random row, a regular background crossed by moving localized structures that collide and interact.",
                width: 400, height: 300, start: .random(seed: 54)
            ),
            total(
                "T1041", 1041, title: "3-color totalistic 1041", behavior: .complexity,
                look: "A growing triangle filling with a mixture of regular stripes and irregular regions.",
                width: 801, height: 400
            ),
            total(
                "T1635", 1635, title: "3-color totalistic 1635", behavior: .complexity,
                look: "Black triangular regions of many sizes separated by textured, irregular zones, with localized structures crossing between them.",
                width: 6101, height: 600, stepLimit: 3000
            ),
            total(
                "T2049", 2049, title: "3-color totalistic 2049", behavior: .complexity,
                look: "A large solid black wedge near the center flanked by long vertical lines, with a busy irregular fringe of small structures along both outer sides.",
                width: 6101, height: 600, stepLimit: 3000
            ),
            total(
                "T1599", 1599, title: "3-color totalistic 1599", behavior: .complexity,
                look: "From one gray cell the pattern grows irregularly for thousands of steps, then regions die out and bursts of growth recur before resolving into many simple repetitive structures.",
                width: 1001, height: 600, stepsPerSecond: 1100, stepLimit: 8300
            ),
            eca(
                "E110.rand", 110, title: "Rule 110, random row", behavior: .complexity,
                look: "Within a few steps a random row organizes into a regular background of small triangles crossed by localized structures that move at different speeds and collide.",
                width: 800, height: 400, start: .random(seed: 1100, density: 0.5), stepLimit: 700
            ),
            total(
                "T1329.seed54889", 1329, title: "3-color totalistic 1329, seed 54889", behavior: .complexity,
                look: "From seed 54889 a complex region widens by about half a cell per step on each side without bound.",
                width: 1201, height: 400, start: .seed(number: 54889, colors: 3)
            ),
            total(
                "T357.seed28", 357, title: "3-color totalistic 357, seed 28", behavior: .complexity,
                look: "Code 357 lets most small seeds die out; seed 28 leaves a persistent structure of 8 to 20 cells.",
                width: 161, height: 300, start: .seed(number: 28, colors: 3)
            ),
        ]
    }
}
