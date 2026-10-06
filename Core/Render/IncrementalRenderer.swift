import CoreGraphics
import Foundation

/// Grows a `ColorGrid` one source row at a time so an animating view does not
/// re-run the whole history on every tick (design doc §6, render ahead). It
/// produces exactly the grid `CPUAutomatonRenderer` would for the same size and
/// step count. Not thread-safe: one queue owns it.
public final class IncrementalRenderer {
    public let spec: ProgramSpec
    public let cols: Int
    public let rows: Int
    /// Total source rows in the run (`min(board.height, stepLimit)`).
    public let totalSteps: Int

    /// The current source row (0 is the seed).
    public private(set) var step = 0
    public private(set) var settled = false

    private var program: any RowProgram
    private var grid: ColorGrid
    private let fit: Fit
    private var nextDisplayRow = 0

    public init(spec: ProgramSpec, cols: Int, rows: Int, steps: Int? = nil) {
        self.spec = spec
        self.cols = max(1, cols)
        self.rows = max(1, rows)
        self.totalSteps = max(1, steps ?? min(spec.board.height, spec.display.stepLimit))
        self.program = spec.makeProgram()
        self.fit = Fit(boardWidth: spec.board.width, displayCols: self.cols, pinRight: spec.display.pinRight)
        self.grid = ColorGrid(cols: self.cols, rows: self.rows)
        fillRowsReady(at: 0)
    }

    public var colorGrid: ColorGrid { grid }

    public var progress: Double {
        totalSteps <= 1 ? 1 : Double(step) / Double(totalSteps - 1)
    }

    /// Advances up to `count` source rows and returns true once settled.
    @discardableResult
    public func advance(by count: Int) -> Bool {
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
        fillRowsReady(at: 0)
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
}
