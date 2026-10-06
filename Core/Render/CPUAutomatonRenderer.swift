import CoreGraphics
import Foundation

/// The always-available render path: runs the `Core/Programs` reference on the
/// calling queue, fits the rows to a `ColorGrid`, and produces a `CGImage`. It
/// is the correctness reference for the Metal path (design doc §5.4.1) and the
/// backend for the CLI and for a machine without a Metal 4 GPU.
public struct CPUAutomatonRenderer: Sendable {
    public init() {}

    /// Renders `spec` into a `cols × rows` grid. `steps` defaults to the
    /// entry's `stepLimit` (the full run); the grid maps those source rows onto
    /// the display rows and blocks of source columns onto the display columns.
    public func grid(
        spec: ProgramSpec,
        cols: Int,
        rows: Int,
        steps: Int? = nil
    ) -> ColorGrid {
        let totalSteps = max(1, steps ?? min(spec.board.height, spec.display.stepLimit))
        let displayCols = max(1, cols)
        let displayRows = max(1, rows)
        let fit = Fit(boardWidth: spec.board.width, displayCols: displayCols, pinRight: spec.display.pinRight)

        var program = spec.makeProgram()
        var computed = 0
        var grid = ColorGrid(cols: displayCols, rows: displayRows)
        for displayRow in 0..<displayRows {
            let target = displayRows == 1 ? totalSteps - 1 : (displayRow * (totalSteps - 1)) / (displayRows - 1)
            while computed < target {
                program.step()
                computed += 1
            }
            let row = program.row()
            for displayCol in 0..<displayCols {
                grid[displayCol, displayRow] = fit.value(in: row, displayCol: displayCol)
            }
        }
        return grid
    }

    public func image(
        spec: ProgramSpec,
        cols: Int,
        rows: Int,
        steps: Int? = nil
    ) -> CGImage? {
        grid(spec: spec, cols: cols, rows: rows, steps: steps)
            .cgImage(palette: spec.display.palette)
    }
}
