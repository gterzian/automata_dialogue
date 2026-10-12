import CoreGraphics
import XCTest
@testable import Core

final class FitTests: XCTestCase {
    private let row: [UInt8] = [1, 0, 1, 1, 0, 0, 1] // width 7

    func testIdentityWhenWidthsMatch() {
        let fit = Fit(boardWidth: 7, displayCols: 7, pinRight: false)
        XCTAssertEqual(fit.block, 1)
        XCTAssertEqual((0..<7).map { fit.value(in: row, displayCol: $0) }, row)
    }

    func testDownsampleMajority() {
        let fit = Fit(boardWidth: 7, displayCols: 3, pinRight: false)
        XCTAssertEqual(fit.block, 3)
        XCTAssertEqual(fit.sourceOrigin, 0)
        // Block 0 = [1,0,1] -> 1; block 1 = [1,0,0] -> 0; block 2 = [1] -> 1.
        XCTAssertEqual((0..<3).map { fit.value(in: row, displayCol: $0) }, [1, 0, 1])
    }

    func testPinRightShowsRightmostBlocks() {
        let fit = Fit(boardWidth: 7, displayCols: 3, pinRight: true)
        XCTAssertEqual(fit.block, 2)
        XCTAssertEqual(fit.sourceOrigin, 1)
        // Blocks: [0,1] -> 0; [1,0] -> 0 (tie -> smaller index); [0,1] -> 0.
        XCTAssertEqual((0..<3).map { fit.value(in: row, displayCol: $0) }, [0, 0, 0])
    }

    func testNarrowBoardIsPaddedNotWrapped() {
        let fit = Fit(boardWidth: 3, displayCols: 7, pinRight: false)
        XCTAssertEqual(fit.padLeft, 2)
        let narrow: [UInt8] = [5, 6, 7]
        XCTAssertEqual((0..<7).map { fit.value(in: narrow, displayCol: $0) }, [0, 0, 5, 6, 7, 0, 0])
    }

    func testNarrowBoardFlushRight() {
        let fit = Fit(boardWidth: 3, displayCols: 7, pinRight: true)
        XCTAssertEqual(fit.padLeft, 4)
        let narrow: [UInt8] = [5, 6, 7]
        XCTAssertEqual((0..<7).map { fit.value(in: narrow, displayCol: $0) }, [0, 0, 0, 0, 5, 6, 7])
    }

    func testNoWrapPastRightEdge() {
        // Width 5, 2 display columns of block 3 -> last block reaches source 6..
        let fit = Fit(boardWidth: 5, displayCols: 2, pinRight: false)
        XCTAssertEqual(fit.block, 3)
        let source: [UInt8] = [1, 1, 1, 1, 1]
        // Second block sources 3,4,5 -> 5 is out of range and ignored, majority 1.
        XCTAssertEqual(fit.value(in: source, displayCol: 1), 1)
    }
}

final class CPURendererTests: XCTestCase {
    func testGridDimensionsAndDeterminism() {
        let spec = Catalog.spec(id: "E90")!
        let renderer = CPUAutomatonRenderer()
        // Render at the board's native width so `fit` uses k = 1. (Downsampling
        // a sparse fractal by majority vote drops its single-cell features; the
        // app renders most entries at native width or upscaled.)
        let a = renderer.grid(spec: spec, cols: 401, rows: 200)
        let b = renderer.grid(spec: spec, cols: 401, rows: 200)
        XCTAssertEqual(a.cols, 401)
        XCTAssertEqual(a.rows, 200)
        XCTAssertEqual(a, b)
        XCTAssertTrue(a.cells.contains(1), "E90 must draw something")
    }

    func testIncrementalMatchesBatch() {
        let renderer = CPUAutomatonRenderer()
        for id in ["E90", "E30", "T1329", "E110"] {
            let spec = Catalog.spec(id: id)!
            let batch = renderer.grid(spec: spec, cols: 80, rows: 40, steps: 120)
            let incremental = IncrementalRenderer(spec: spec, cols: 80, rows: 40, steps: 120)
            while !incremental.advance(by: 7) {}
            XCTAssertEqual(incremental.colorGrid, batch, id)
        }
    }

    func testIncrementalSettlesAtTotalSteps() {
        let spec = Catalog.spec(id: "E30")!
        let incremental = IncrementalRenderer(spec: spec, cols: 40, rows: 20, steps: 50)
        XCTAssertFalse(incremental.settled)
        XCTAssertTrue(incremental.advance(by: 50))
        XCTAssertTrue(incremental.settled)
        XCTAssertEqual(incremental.step, 49)
        XCTAssertNotNil(incremental.image())
    }

    /// A scrolling run grows from the top until the display is full, then
    /// keeps the newest row at the bottom and shows the source rows above it.
    func testScrollingGrowsThenKeepsNewestRowAtBottom() {
        let spec = Catalog.spec(id: "E90")!
        let rows = 10
        let incremental = IncrementalRenderer(spec: spec, cols: spec.board.width, rows: rows, scrolling: true)
        XCTAssertFalse(incremental.settled)

        // Only the seed row is drawn; the rest of the window is background.
        XCTAssertTrue((0..<incremental.cols).contains { incremental.colorGrid[$0, 0] == 1 })
        for row in 1..<rows {
            XCTAssertTrue((0..<incremental.cols).allSatisfy { incremental.colorGrid[$0, row] == 0 })
        }

        // Past the fill point the bottom row is the newest source row and the
        // top row is `rows - 1` steps older.
        incremental.advance(by: 25)
        XCTAssertEqual(incremental.step, 25)
        let fit = Fit(boardWidth: spec.board.width, displayCols: incremental.cols, pinRight: spec.display.pinRight)
        var program = spec.makeProgram()
        var source: [[UInt8]] = [program.row()]
        while source.count <= incremental.step {
            program.step()
            source.append(program.row())
        }
        for displayRow in 0..<rows {
            let sourceStep = incremental.step - (rows - 1) + displayRow
            let expected = (0..<incremental.cols).map { fit.value(in: source[sourceStep], displayCol: $0) }
            let actual = (0..<incremental.cols).map { incremental.colorGrid[$0, displayRow] }
            XCTAssertEqual(actual, expected, "row \(displayRow)")
        }
    }

    func testColorGridRGBAAndImage() {
        var grid = ColorGrid(cols: 2, rows: 1)
        grid[0, 0] = 0
        grid[1, 0] = 1
        let palette = Palette.standard(stateCount: 2)
        XCTAssertEqual(grid.rgbaBytes(palette: palette).count, 8)
        let image = grid.cgImage(palette: palette)
        XCTAssertEqual(image?.width, 2)
        XCTAssertEqual(image?.height, 1)
    }
}
