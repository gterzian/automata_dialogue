import CoreGraphics
import Foundation

/// Grows a `ColorGrid` one source row at a time so an animating view does not
/// re-run the whole history on every tick. It
/// produces exactly the grid `CPUAutomatonRenderer` would for the same size and
/// step count. Not thread-safe: one queue owns it.
public final class IncrementalRenderer {
    public let spec: ProgramSpec
    public let cols: Int
    public let rows: Int
    /// Total source rows in the run (`min(board.height, stepLimit)`), or
    /// `Int.max` in scrolling mode, where the run has no end.
    public let totalSteps: Int
    /// When true, display row `d` shows source step `step - (rows - 1) + d`,
    /// so the newest row stays at the bottom and older rows scroll off the
    /// top. When false, the whole run is stretched across the display.
    public let scrolling: Bool

    /// The current source row (0 is the seed).
    public private(set) var step = 0
    public private(set) var settled = false

    private var program: any RowProgram
    private var grid: ColorGrid
    private let fit: Fit
    private var nextDisplayRow = 0
    /// Scrolling history ring; the source step indexes it modulo `capacity`.
    private let capacity: Int
    private var ring: [[UInt8]]

    public init(spec: ProgramSpec, cols: Int, rows: Int, steps: Int? = nil, scrolling: Bool = false) {
        let displayCols = max(1, cols)
        let displayRows = max(1, rows)
        self.spec = spec
        self.cols = displayCols
        self.rows = displayRows
        self.scrolling = scrolling
        self.totalSteps = scrolling
            ? Int.max
            : max(1, steps ?? min(spec.board.height, spec.display.stepLimit))
        self.capacity = displayRows + 2
        self.program = spec.makeProgram()
        self.fit = Fit(boardWidth: spec.board.width, displayCols: displayCols, pinRight: spec.display.pinRight)
        self.grid = ColorGrid(cols: displayCols, rows: displayRows)
        self.ring = Array(repeating: [], count: displayRows + 2)
        if scrolling {
            ring[0] = program.row()
            refit()
        } else {
            fillRowsReady(at: 0)
        }
    }

    public var colorGrid: ColorGrid { grid }

    public var progress: Double {
        totalSteps <= 1 ? 1 : Double(step) / Double(totalSteps - 1)
    }

    /// Advances up to `count` source rows and returns true once settled. A
    /// scrolling run never settles.
    @discardableResult
    public func advance(by count: Int) -> Bool {
        if scrolling {
            let target = step + max(0, count)
            while step < target {
                program.step()
                step += 1
                ring[step % capacity] = program.row()
            }
            refit()
            return false
        }
        guard !settled else { return true }
        let target = min(totalSteps - 1, step + max(0, count))
        while step < target {
            program.step()
            step += 1
            fillRowsReady(at: step)
        }
        if step >= totalSteps - 1 {
            settled = true
        }
        return settled
    }

    public func reset() {
        program = spec.makeProgram()
        step = 0
        settled = false
        grid = ColorGrid(cols: cols, rows: rows)
        nextDisplayRow = 0
        if scrolling {
            for index in ring.indices { ring[index] = [] }
            ring[0] = program.row()
            refit()
        } else {
            fillRowsReady(at: 0)
        }
    }

    public func image() -> CGImage? {
        grid.cgImage(palette: spec.display.palette)
    }

    // MARK: - Private

    /// The source step that display row `d` shows. Matches
    /// `CPUAutomatonRenderer.grid`.
    private func targetStep(forDisplayRow d: Int) -> Int {
        rows == 1 ? totalSteps - 1 : (d * (totalSteps - 1)) / (rows - 1)
    }

    /// Fills every display row whose target step has now been reached.
    private func fillRowsReady(at sourceStep: Int) {
        let row = program.row()
        while nextDisplayRow < rows, targetStep(forDisplayRow: nextDisplayRow) <= sourceStep {
            for col in 0..<cols {
                grid[col, nextDisplayRow] = fit.value(in: row, displayCol: col)
            }
            nextDisplayRow += 1
        }
    }

    /// Refits the whole scrolling window from the ring of recent source rows.
    /// Display rows the run has not reached yet stay background, so a short
    /// board grows from the top before it starts to scroll.
    private func refit() {
        let viewportStart = max(0, step - (rows - 1))
        for displayRow in 0..<rows {
            let sourceStep = viewportStart + displayRow
            guard sourceStep <= step else {
                for col in 0..<cols { grid[col, displayRow] = 0 }
                continue
            }
            let row = ring[sourceStep % capacity]
            for col in 0..<cols { grid[col, displayRow] = fit.value(in: row, displayCol: col) }
        }
    }
}
