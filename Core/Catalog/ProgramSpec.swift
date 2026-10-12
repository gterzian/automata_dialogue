import Foundation

/// How the GPU advances an entry.
public enum GPUProgram: Sendable, Hashable {
    /// Radius 1, 2 colors; `rule` is the Wolfram code.
    case elementary(rule: UInt8)
    /// Radius 1, `colors` colors; `code` is the base-`colors` totalistic code.
    case totalistic(code: UInt32, colors: UInt8)
    /// Radius 2, 2 colors; `code` is the 6-bit next-nearest-neighbor
    /// totalistic code, digit `s` the new color for sum `s` (inventory §1.3).
    case k2r2(code: UInt16)
}

/// The seed row of a board. Mirrors `ElementaryCA.Start`; totalistic entries
/// always use a single gray cell and ignore `random`.
public enum BoardStart: Sendable, Hashable {
    case center
    case rightmost
    /// Each cell is on with `density` (inventory §1.4).
    case random(seed: UInt64, density: Double = 0.5)
    /// Random 2-cell blocks, each entirely on or entirely off (inventory §1.4).
    case randomBlocks(seed: UInt64)
    /// A fixed block repeated across the row (inventory §1.4).
    case block([UInt8])
    /// `number` written in base `colors`, most significant digit first, from
    /// the center cell (inventory §1.4).
    case seed(number: Int, colors: Int)
}

public struct Board: Sendable, Hashable {
    public var width: Int
    public var height: Int
    public var start: BoardStart

    public init(width: Int, height: Int, start: BoardStart = .center) {
        self.width = width
        self.height = height
        self.start = start
    }
}

/// Per-entry run settings.
public struct DisplayHints: Sendable, Hashable {
    /// Steps advanced per second of wall time. The surface accumulates
    /// `Δt × stepsPerSecond` and caps each tick at 64 steps.
    public var stepsPerSecond: Double
    /// Total steps before the pattern settles and the clock pauses. Defaults
    /// to four times the board height; a few long-transient
    /// entries override it.
    public var stepLimit: Int
    /// E110 grows leftward from the rightmost cell; the view follows the
    /// newest rows pinned to the right edge.
    public var pinRight: Bool
    public var palette: Palette

    public init(stepsPerSecond: Double, stepLimit: Int, pinRight: Bool = false, palette: Palette) {
        self.stepsPerSecond = stepsPerSecond
        self.stepLimit = stepLimit
        self.pinRight = pinRight
        self.palette = palette
    }
}

/// One row of the single table that feeds the renderer and the prompt index.
/// `reference` builds the CPU program that the GPU kernels are tested against.
public struct ProgramSpec: Sendable {
    public let id: String
    public let title: String
    public let behavior: Behavior
    /// One sentence of how the entry looks. Used as the matching text in the
    /// system prompt's automata listing.
    public let look: String
    public let gpu: GPUProgram
    public let board: Board
    public let display: DisplayHints
    /// Builds the CPU `RowProgram` for a board. The catalog routes this through
    /// `ProgramFactory`, so the mapping from `GPUProgram`/`Board` to a concrete
    /// program lives in one place.
    public let reference: @Sendable (Board) -> any RowProgram

    public init(
        id: String,
        title: String,
        behavior: Behavior,
        look: String,
        gpu: GPUProgram,
        board: Board,
        display: DisplayHints,
        reference: @escaping @Sendable (Board) -> any RowProgram
    ) {
        self.id = id
        self.title = title
        self.behavior = behavior
        self.look = look
        self.gpu = gpu
        self.board = board
        self.display = display
        self.reference = reference
    }

    /// A fresh CPU program for this entry's stored board. Deterministic, so it
    /// is the entry point for the golden hashes and the CPU/GPU comparison.
    public func makeProgram() -> any RowProgram { reference(board) }

    /// A copy whose `.rand` start draws from `seed`; a start that is not a
    /// random row is returned unchanged. Each app run calls this with a fresh
    /// seed so re-choosing an entry gives a different picture, while
    /// `makeProgram()` stays deterministic for the tests.
    public func withRandomSeed(_ seed: UInt64) -> ProgramSpec {
        guard case .random(_, let density) = board.start else { return self }
        let reseeded = Board(width: board.width, height: board.height,
                             start: .random(seed: seed, density: density))
        return ProgramSpec(
            id: id, title: title, behavior: behavior, look: look,
            gpu: gpu, board: reseeded, display: display, reference: reference)
    }

    public var stateCount: Int {
        switch gpu {
        case .elementary: 2
        case .totalistic(_, let colors): Int(colors)
        case .k2r2: 2
        }
    }
}
