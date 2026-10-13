import Foundation

/// The curated inventory as one table. Exactly 111 entries, in
/// the inventory's order; the system prompt's automata listing and the CLI
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

    /// One line per entry: `id | class | look`. The system prompt embeds the
    /// flat list, so each entry carries its class instead of being grouped.
    public static var promptIndexLines: [String] {
        all.map { "\($0.id) | \($0.behavior.rawValue) | \($0.look)" }
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
        follow: Follow = .none,
        stepsPerSecond: Double? = nil,
        stepLimit: Int? = nil
    ) -> ProgramSpec {
        let display = DisplayHints(
            stepsPerSecond: stepsPerSecond ?? defaultStepsPerSecond(height: board.height),
            stepLimit: stepLimit ?? board.height * 4,
            pinRight: pinRight,
            follow: follow,
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
            reference: { ProgramFactory.make(gpu: gpu, board: $0) }
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
        injection: RandomInjection? = nil,
        pinRight: Bool = false,
        follow: Follow = .none,
        stepsPerSecond: Double? = nil,
        stepLimit: Int? = nil
    ) -> ProgramSpec {
        make(
            id: id, title: title, behavior: behavior, look: look,
            gpu: .elementary(rule: rule),
            board: Board(width: width, height: height, start: start, injection: injection),
            pinRight: pinRight, follow: follow, stepsPerSecond: stepsPerSecond, stepLimit: stepLimit
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
        injection: RandomInjection? = nil,
        follow: Follow = .none,
        stepsPerSecond: Double? = nil,
        stepLimit: Int? = nil
    ) -> ProgramSpec {
        make(
            id: id, title: title, behavior: behavior, look: look,
            gpu: .totalistic(code: code, colors: 3),
            board: Board(width: width, height: height, start: start, injection: injection),
            follow: follow, stepsPerSecond: stepsPerSecond, stepLimit: stepLimit
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
        injection: RandomInjection? = nil,
        follow: Follow = .none,
        stepsPerSecond: Double? = nil,
        stepLimit: Int? = nil
    ) -> ProgramSpec {
        make(
            id: id, title: title, behavior: behavior, look: look,
            gpu: .k2r2(code: code),
            board: Board(width: width, height: height, start: start, injection: injection),
            follow: follow, stepsPerSecond: stepsPerSecond, stepLimit: stepLimit
        )
    }

    private static func makeAll() -> [ProgramSpec] {
        [
            // MARK: Repetition (27)
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
            eca(
                "E28", 28, title: "Rule 28", behavior: .repetition,
                look: "A wedge of evenly spaced vertical stripes grows down and to the right from a single cell, with a clean diagonal edge and empty white on the left.",
                width: 321, height: 160, follow: .right
            ),
            eca(
                "E94", 94, title: "Rule 94", behavior: .repetition,
                look: "A clean triangle filled with evenly spaced vertical stripes, edged by two sharp diagonals.",
                width: 401, height: 200
            ),
            // E62's single-cell triangle reads as busy, but its interior is a
            // period-3 weave (verified: rows t and t+3 agree across the whole
            // triangle, and every column is eventually period 3), so it is a
            // repetition rule, not complexity.
            eca(
                "E62", 62, title: "Rule 62", behavior: .repetition,
                look: "From a single cell a triangle grows, its interior a fine diagonal weave that repeats every three steps: even striping on the left, a denser fan on the right.",
                width: 801, height: 400
            ),
            eca(
                "E77", 77, title: "Rule 77", behavior: .repetition,
                look: "Horizontal stripes bend into evenly spaced right-angle corners that fan out from the top center.",
                width: 321, height: 160
            ),
            eca(
                "E57", 57, title: "Rule 57", behavior: .repetition,
                look: "A horizontally striped field with a central wedge of fine woven texture widening downward, lighter on its left half and darker on its right.",
                width: 321, height: 160
            ),
            eca(
                "E54", 54, title: "Rule 54", behavior: .repetition,
                look: "A growing triangle filled with a tight regular lattice of tiny triangles, like woven cloth.",
                width: 321, height: 160
            ),
            eca(
                "E73", 73, title: "Rule 73", behavior: .repetition,
                look: "A symmetric triangle of stacked arches with a dotted core grows over a horizontally striped background.",
                width: 401, height: 200
            ),
            total(
                "T1047", 1047, title: "3-color totalistic 1047", behavior: .repetition,
                look: "A dark triangle filled with thin horizontal stripes, with a ragged light fringe along its edges.",
                width: 321, height: 160
            ),
            total(
                "T183", 183, title: "3-color totalistic 183", behavior: .repetition,
                look: "A triangle of fine black-and-white checker lattice split by one vertical seam down the center.",
                width: 321, height: 160
            ),
            total(
                "T600", 600, title: "3-color totalistic 600", behavior: .repetition,
                look: "A narrow column of stacked, textured gray triangles, 11 to 25 cells wide, whose bands recur down the screen.",
                width: 161, height: 300
            ),
            total(
                "T1329", 1329, title: "3-color totalistic 1329", behavior: .repetition,
                look: "A narrow column of large gray-and-black triangular bands, 9 to 23 cells wide, whose shape repeats exactly every 78 steps.",
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
                look: "The block black-black-white-white repeated across the row weaves a fine diagonal lattice with period 8 in time and 4 cells across.",
                width: 320, height: 160, start: .block([1, 1, 0, 0])
            ),
            k2r2(
                "K2R2-20.seed195", 20, title: "K2R2 code 20, seed 195", behavior: .repetition,
                look: "From the cells black-black-white-white-white-white-black-black a column 8 to 28 cells wide forms, and its shape repeats every 22 steps.",
                width: 221, height: 220, start: .seed(number: 195, colors: 2)
            ),
            total(
                "T1329.seed916", 1329, title: "3-color totalistic 1329, seed 916", behavior: .repetition,
                look: "From seed 916 a compact object 16 to 32 cells wide drifts slowly across the white background.",
                width: 321, height: 300, start: .seed(number: 916, colors: 3),
                follow: Follow(columnsPerStep: 0.22)
            ),
            total(
                "T357.seed28", 357, title: "3-color totalistic 357, seed 28", behavior: .repetition,
                look: "From seed 28 a persistent column of stacked triangular structures, between 8 and 28 cells wide, runs on through at least 1500 steps.",
                width: 161, height: 300, start: .seed(number: 28, colors: 3), stepLimit: 1600
            ),
            eca(
                "E184.rand", 184, title: "Rule 184, random row", behavior: .repetition,
                look: "Parallel diagonal stripes of black and white sweep across the picture, with a few wedge-shaped jams that dissolve into the stripes.",
                width: 400, height: 200, start: .random(seed: 184, density: 0.5)
            ),
            eca(
                "E178.rand", 178, title: "Rule 178, random row", behavior: .repetition,
                look: "A woven zigzag texture runs down the picture in vertical columns separated by faint seams.",
                width: 400, height: 300, start: .random(seed: 178, density: 0.5)
            ),
            eca(
                "E15.rand", 15, title: "Rule 15, random row", behavior: .repetition,
                look: "Smooth wavy ribbons curve diagonally across the picture.",
                width: 400, height: 300, start: .random(seed: 15, density: 0.5)
            ),
            eca(
                "E14.rand", 14, title: "Rule 14, random row", behavior: .repetition,
                look: "Thick parallel diagonal stripes lean to the right, with a few broader bands crossing them.",
                width: 400, height: 300, start: .random(seed: 14, density: 0.5)
            ),
            total(
                "T1587.rand", 1587, title: "3-color totalistic 1587, random row", behavior: .repetition,
                look: "A flat gray field crossed by evenly spaced vertical columns of small beaded structures.",
                width: 400, height: 300, start: .random(seed: 1587)
            ),

            // MARK: Nesting (28)
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
                width: 401, height: 200, follow: .right
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
            eca(
                "E18", 18, title: "Rule 18", behavior: .nesting,
                look: "The Sierpinski triangle drawn as sparse isolated dots, airy and light, with white triangular holes at every scale.",
                width: 401, height: 200
            ),
            eca(
                "E126", 126, title: "Rule 126", behavior: .nesting,
                look: "A bold Sierpinski triangle with thick black edges and white triangular holes at every scale.",
                width: 401, height: 200
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
            total(
                "T561", 561, title: "3-color totalistic 561", behavior: .nesting,
                look: "A black-edged triangle packed with small white triangular holes of many sizes.",
                width: 401, height: 200
            ),
            total(
                "T399", 399, title: "3-color totalistic 399", behavior: .nesting,
                look: "A dense triangle of fine gray-and-black lines with white triangular holes at many sizes.",
                width: 401, height: 200
            ),
            total(
                "T1182", 1182, title: "3-color totalistic 1182", behavior: .nesting,
                look: "Nested triangles on a mid-gray ground: flat gray holes at several scales framed by fine black texture.",
                width: 401, height: 200
            ),
            total(
                "T1419", 1419, title: "3-color totalistic 1419", behavior: .nesting,
                look: "Large flat gray triangular holes at several scales set in a black lace.",
                width: 401, height: 200
            ),
            total(
                "T1848", 1848, title: "3-color totalistic 1848", behavior: .nesting,
                look: "Solid black triangular voids at several scales set in a gray lace with a pale outline.",
                width: 401, height: 200
            ),
            total(
                "T1932", 1932, title: "3-color totalistic 1932", behavior: .nesting,
                look: "Heavy solid black triangular voids at every scale in a dark lace, the darkest of the Sierpinski-like forms.",
                width: 401, height: 200
            ),
            total(
                "T885", 885, title: "3-color totalistic 885", behavior: .nesting,
                look: "Nested triangles surround a core of tight horizontal stripes that widens toward the bottom.",
                width: 401, height: 200
            ),
            total(
                "T1284", 1284, title: "3-color totalistic 1284", behavior: .nesting,
                look: "Nested triangles on either side of a central core of vertical stripes.",
                width: 401, height: 200
            ),
            total(
                "T453", 453, title: "3-color totalistic 453", behavior: .nesting,
                look: "Bold black branching clusters nested inside white triangular voids, a stout tree-like fractal.",
                width: 401, height: 200
            ),
            total(
                "T1509", 1509, title: "3-color totalistic 1509", behavior: .nesting,
                look: "Slender black branching trees nested inside large white triangular voids.",
                width: 401, height: 200
            ),
            total(
                "T273", 273, title: "3-color totalistic 273", behavior: .nesting,
                look: "A pale gray lace of nested triangles with fine vertical spars.",
                width: 401, height: 200
            ),
            total(
                "T1410", 1410, title: "3-color totalistic 1410", behavior: .nesting,
                look: "A narrow steep triangle filled with dark nested structure.",
                width: 321, height: 200
            ),
            k2r2(
                "K2R2-2", 2, title: "K2R2 code 2", behavior: .nesting,
                look: "Sparse nested triangles spread wide and shallow, with large flat white wedges between them.",
                width: 401, height: 100
            ),
            k2r2(
                "K2R2-30", 30, title: "K2R2 code 30", behavior: .nesting,
                look: "Bold black outlines of nested triangles spread wide and shallow.",
                width: 401, height: 100
            ),
            k2r2(
                "K2R2-42", 42, title: "K2R2 code 42", behavior: .nesting,
                look: "Wide, shallow nested triangles whose edges sprout small branching trees.",
                width: 401, height: 100
            ),

            // MARK: Randomness (36)
            eca(
                "E30", 30, title: "Rule 30", behavior: .randomness,
                look: "A disordered black-and-white field of static with scattered white triangles of every size.",
                width: 401, height: 200, start: .random(seed: 30, density: 0.5)
            ),
            eca(
                "E45", 45, title: "Rule 45", behavior: .randomness,
                look: "Dense black-and-white static with short vertical dashes and irregular blocks.",
                width: 401, height: 200, start: .random(seed: 45, density: 0.5)
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
            total(
                "T138", 138, title: "3-color totalistic 138", behavior: .randomness,
                look: "A triangle of irregular white-flecked mottling in gray and black.",
                width: 601, height: 300
            ),
            total(
                "T867", 867, title: "3-color totalistic 867", behavior: .randomness,
                look: "A triangle of bright speckle with a mirror-symmetric, kaleidoscope-like center.",
                width: 601, height: 300
            ),
            total(
                "T1473", 1473, title: "3-color totalistic 1473", behavior: .randomness,
                look: "A triangle of fine speckle with scattered white triangular gaps.",
                width: 601, height: 300
            ),
            total(
                "T1929", 1929, title: "3-color totalistic 1929", behavior: .randomness,
                look: "A dark triangle of black-and-gray static with black triangular patches of many sizes.",
                width: 601, height: 300
            ),
            total(
                "T777", 777, title: "3-color totalistic 777", behavior: .randomness,
                look: "A triangle of black-and-white noise with a mirror line down the center and small white triangles scattered through it.",
                width: 601, height: 300
            ),
            k2r2(
                "K2R2-10", 10, title: "K2R2 code 10", behavior: .randomness,
                look: "Fine random speckle with faint banding.",
                width: 401, height: 100, start: .random(seed: 10, density: 0.5)
            ),
            k2r2(
                "K2R2-50", 50, title: "K2R2 code 50", behavior: .randomness,
                look: "Random speckle dotted with bold black inverted triangles.",
                width: 401, height: 100, start: .random(seed: 50, density: 0.5)
            ),
            eca(
                "E90.rand", 90, title: "Rule 90, random row", behavior: .randomness,
                look: "A random field with white triangles at every size; rule 90 adds shifted copies of its single-cell triangle, so the picture carries the initial row's randomness.",
                width: 401, height: 200, start: .random(seed: 90, density: 0.5)
            ),
            eca(
                "E90.inject", 90, title: "Rule 90, injected randomness", behavior: .randomness,
                look: "Rule 90 with one random cell injected every step: a dense lace of overlapping triangles at every size.",
                width: 401, height: 200, injection: RandomInjection(seed: 90)
            ),
            eca(
                "E105.rand", 105, title: "Rule 105, random row", behavior: .randomness,
                look: "Dense black-and-white static with white triangles of many sizes scattered through it.",
                width: 401, height: 200, start: .random(seed: 105, density: 0.5)
            ),
            eca(
                "E129.rand", 129, title: "Rule 129, random row", behavior: .randomness,
                look: "A dark field of irregular texture broken by black triangles of many sizes.",
                width: 401, height: 200, start: .random(seed: 129, density: 0.5)
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
            eca(
                "E126.pairs", 126, title: "Rule 126, 2-cell blocks", behavior: .randomness,
                look: "Random black-black and white-white pairs evolve into a dense field of triangles of many sizes.",
                width: 400, height: 200, start: .randomBlocks(seed: 126)
            ),
            eca(
                "E90.sparse", 90, title: "Rule 90, sparse random row", behavior: .randomness,
                look: "Sparse speckle at density 0.05 spawns overlapping triangles of every size that pile up into a dense lace, and the thin speckle returns at steps that are powers of two.",
                width: 1001, height: 200, start: .random(seed: 905, density: 0.05)
            ),
            eca(
                "E150.rand", 150, title: "Rule 150, random row", behavior: .randomness,
                look: "Dense black-and-white static with small dark clumps and no visible structure.",
                width: 400, height: 300, start: .random(seed: 150, density: 0.5)
            ),
            eca(
                "E18.rand", 18, title: "Rule 18, random row", behavior: .randomness,
                look: "Sparse speckle with white triangles of many sizes scattered across it.",
                width: 400, height: 300, start: .random(seed: 18, density: 0.5)
            ),
            eca(
                "E60.rand", 60, title: "Rule 60, random row", behavior: .randomness,
                look: "A dense random texture crossed by small black and white triangles that lean to the right.",
                width: 400, height: 300, start: .random(seed: 60, density: 0.5)
            ),
            eca(
                "E232.rand", 232, title: "Rule 232, random row", behavior: .randomness,
                look: "Vertical bars of random width in black and white, frozen from the first rows.",
                width: 400, height: 300, start: .random(seed: 232, density: 0.5)
            ),
            eca(
                "E170.rand", 170, title: "Rule 170, random row", behavior: .randomness,
                look: "Thick diagonal stripes of irregular widths lean to the right.",
                width: 400, height: 300, start: .random(seed: 170, density: 0.5)
            ),
            eca(
                "E2.rand", 2, title: "Rule 2, random row", behavior: .randomness,
                look: "Thin diagonal lines lean to the right, scattered at irregular spacing across white.",
                width: 400, height: 300, start: .random(seed: 2, density: 0.5)
            ),
            total(
                "T237.rand", 237, title: "3-color totalistic 237, random row", behavior: .randomness,
                look: "Dense random black-and-white texture with white triangles of many sizes scattered throughout.",
                width: 601, height: 300, start: .random(seed: 237)
            ),
            total(
                "T1182.rand", 1182, title: "3-color totalistic 1182, random row", behavior: .randomness,
                look: "A mid-gray mottled field with gray triangles of many sizes.",
                width: 601, height: 300, start: .random(seed: 1182)
            ),
            // Random rows of the nested entries (inventory §1.4): the same rule
            // from a random row loses the self-similarity and reads as disorder,
            // so each gets its own randomness entry rather than reusing the
            // single-cell one.
            eca(
                "E225.rand", 225, title: "Rule 225, random row", behavior: .randomness,
                look: "Thin diagonal strokes scattered at irregular spacing across a black field.",
                width: 401, height: 300, start: .random(seed: 225, density: 0.5)
            ),
            total(
                "T1848.rand", 1848, title: "3-color totalistic 1848, random row", behavior: .randomness,
                look: "A black field strewn with white triangle outlines of many sizes.",
                width: 401, height: 200, start: .random(seed: 1848)
            ),
            total(
                "T1932.rand", 1932, title: "3-color totalistic 1932, random row", behavior: .randomness,
                look: "A dark field with white triangles of many sizes.",
                width: 401, height: 200, start: .random(seed: 1932)
            ),
            total(
                "T1410.rand", 1410, title: "3-color totalistic 1410, random row", behavior: .randomness,
                look: "A narrow steep column of dense gray-and-black speckle.",
                width: 321, height: 200, start: .random(seed: 1410)
            ),
            k2r2(
                "K2R2-2.rand", 2, title: "K2R2 code 2, random row", behavior: .randomness,
                look: "Sparse speckle that spawns white triangles of many sizes.",
                width: 401, height: 100, start: .random(seed: 2, density: 0.5)
            ),
            k2r2(
                "K2R2-30.rand", 30, title: "K2R2 code 30, random row", behavior: .randomness,
                look: "Dense speckle with white triangular outlines at many sizes.",
                width: 401, height: 100, start: .random(seed: 30, density: 0.5)
            ),
            k2r2(
                "K2R2-42.rand", 42, title: "K2R2 code 42, random row", behavior: .randomness,
                look: "Dense mottled speckle with small white triangles.",
                width: 401, height: 100, start: .random(seed: 42, density: 0.5)
            ),

            // MARK: Complex localized structures (20)
            eca(
                "E110", 110, title: "Rule 110", behavior: .complexity,
                look: "From a single cell the pattern grows to one side: a regular background of small triangles with localized structures of many sizes traveling through it and colliding.",
                width: 1201, height: 400, start: .rightmost, pinRight: true
            ),
            eca(
                "E110.rand", 110, title: "Rule 110, random row", behavior: .complexity,
                look: "Within a few steps a random row organizes into a regular background of small triangles crossed by localized structures that move at different speeds and collide.",
                width: 800, height: 400, start: .random(seed: 1100, density: 0.5), stepLimit: 700
            ),
            eca(
                "E54.rand", 54, title: "Rule 54, random row", behavior: .complexity,
                look: "From a random row, a regular background crossed by moving localized structures that collide and interact.",
                width: 400, height: 300, start: .random(seed: 54, density: 0.5)
            ),
            eca(
                "E106.rand", 106, title: "Rule 106, random row", behavior: .complexity,
                look: "Diagonal strokes and white triangles of many sizes interlock across the picture, with irregular regions between them.",
                width: 400, height: 300, start: .random(seed: 106, density: 0.5)
            ),
            eca(
                "E154.rand", 154, title: "Rule 154, random row", behavior: .complexity,
                look: "Broad diagonal black bands cross a speckled field, with irregular textured regions between them.",
                width: 400, height: 300, start: .random(seed: 154, density: 0.5)
            ),
            total(
                "T1041", 1041, title: "3-color totalistic 1041", behavior: .complexity,
                look: "A mixture of regular vertical stripes and irregular regions.",
                width: 801, height: 400, start: .random(seed: 1041)
            ),
            total(
                "T1599", 1599, title: "3-color totalistic 1599", behavior: .complexity,
                look: "A field of irregular trees and columns that grow, die out and return.",
                width: 1001, height: 600, start: .random(seed: 1599), stepsPerSecond: 1100, stepLimit: 8300
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
                "T1662", 1662, title: "3-color totalistic 1662", behavior: .complexity,
                look: "Vertical black columns strung with beaded structures.",
                width: 801, height: 400, start: .random(seed: 1662)
            ),
            total(
                "T1329.seed54889", 1329, title: "3-color totalistic 1329, seed 54889", behavior: .complexity,
                look: "From seed 54889 a complex region widens by about half a cell per step in total, drifting slowly to one side without bound.",
                width: 1201, height: 400, start: .seed(number: 54_889, colors: 3),
                follow: Follow(columnsPerStep: 0.37)
            ),
            total(
                "T1635.rand", 1635, title: "3-color totalistic 1635, random row", behavior: .complexity,
                look: "Black voids and bright textured regions are split by tall branching structures that grow, collide and merge.",
                width: 800, height: 400, start: .random(seed: 1635)
            ),
            total(
                "T2049.rand", 2049, title: "3-color totalistic 2049, random row", behavior: .complexity,
                look: "A black field with thin gray vertical lines, hung with branching white trees that reach down from above.",
                width: 800, height: 400, start: .random(seed: 2049)
            ),
            total(
                "T2046.rand", 2046, title: "3-color totalistic 2046, random row", behavior: .complexity,
                look: "A black field with clusters of branching white trees growing and merging near the center.",
                width: 800, height: 400, start: .random(seed: 2046)
            ),
            total(
                "T1329.rand", 1329, title: "3-color totalistic 1329, random row", behavior: .complexity,
                look: "A white field with gray triangles and black trees that grow downward and collide.",
                width: 800, height: 400, start: .random(seed: 1329),
            ),
            total(
                "T357.rand", 357, title: "3-color totalistic 357, random row", behavior: .complexity,
                look: "White voids with gray-and-black trees of many sizes growing into them.",
                width: 800, height: 400, start: .random(seed: 357),
            ),
            total(
                "T948.rand", 948, title: "3-color totalistic 948, random row", behavior: .complexity,
                look: "Bold black-and-white branching structures at diagonal angles that run into each other.",
                width: 800, height: 400, start: .random(seed: 948)
            ),
            total(
                "T1920.rand", 1920, title: "3-color totalistic 1920, random row", behavior: .complexity,
                look: "Black columns split by bright vertical seams, each filled with nested triangles of its own size.",
                width: 800, height: 400, start: .random(seed: 1920)
            ),
            total(
                "T219.rand", 219, title: "3-color totalistic 219, random row", behavior: .complexity,
                look: "A sparse white field crossed by vertical lines and diagonal strands that meet and bend.",
                width: 800, height: 400, start: .random(seed: 219)
            ),
            k2r2(
                "K2R2-52.rand", 52, title: "K2R2 code 52, random row", behavior: .complexity,
                look: "Large black and white regions bounded by long vertical and diagonal edges, with small branching structures at their junctions.",
                width: 600, height: 400, start: .random(seed: 52, density: 0.5),
            ),
        ]
    }
}
