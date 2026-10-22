import Metal
import XCTest
@testable import Core

/// A basic smoke test of the GPU `seed`/`step`/`fit` kernels: the seed row
/// appears, and advancing fills the window. Skipped with no Metal 4 device.
final class MetalTests: XCTestCase {
    func testSeedAndAdvanceFillTheWindow() throws {
        guard GPUContext.isAvailable else {
            throw XCTSkip("no Metal 4 device")
        }
        let context = try GPUContext()
        let spec = Catalog.spec(id: "E90")!
        let cols = 61
        let rows = 40
        let simulation = try MetalSimulation(spec: spec, cols: cols, rows: rows, context: context)

        let seed = try simulation.renderGPU(chunk: 0)
        XCTAssertEqual(nonZero(seed), 1, "the seed is a single center cell")

        let grown = try simulation.renderGPU(chunk: 20)
        XCTAssertGreaterThan(nonZero(grown), 1, "advancing must grow the pattern")
    }

    private func nonZero(_ grid: GPUColorGrid) -> Int {
        let cells = grid.buffer.contents().bindMemory(to: UInt8.self, capacity: grid.cols * grid.rows)
        var count = 0
        for index in 0..<(grid.cols * grid.rows) where cells[index] != 0 { count += 1 }
        return count
    }

    /// The `seed_row` kernel must reproduce each `BoardStart` shape. A board as
    /// wide as the window keeps the whole seed row visible.
    func testSeedShapes() throws {
        guard GPUContext.isAvailable else { throw XCTSkip("no Metal 4 device") }
        let context = try GPUContext()
        let cols = 64

        func seedRow(id: String, start: BoardStart) throws -> [UInt8] {
            let base = try XCTUnwrap(Catalog.spec(id: id))
            let spec = ProgramSpec(
                id: base.id, title: base.title, behavior: base.behavior,
                look: base.look, gpu: base.gpu, board: base.board, display: base.display)
            let board = Board(width: cols, height: 8, start: start)
            let simulation = try MetalSimulation(
                spec: spec, cols: cols, rows: 4, context: context, board: board)
            let grid = try simulation.renderGPU(chunk: 0)
            let cells = grid.buffer.contents().bindMemory(to: UInt8.self, capacity: cols * 4)
            return (0..<cols).map { cells[$0] }
        }

        let center = try seedRow(id: "E90", start: .center)
        XCTAssertEqual((0..<cols).filter { center[$0] != 0 }, [cols / 2])

        let rightmost = try seedRow(id: "E110", start: .rightmost)
        XCTAssertEqual((0..<cols).filter { rightmost[$0] != 0 }, [cols - 1])

        let block = try seedRow(id: "E30.block1100", start: .block([1, 1, 0, 0]))
        XCTAssertEqual(block, (0..<cols).map { UInt8(($0 % 4) < 2 ? 1 : 0) })

        // 195 = 0b11000011, most significant digit first, from the center.
        let seeded = try seedRow(id: "K2R2-20.seed195", start: .seed(number: 195, colors: 2))
        XCTAssertEqual(seeded[(cols / 2)..<(cols / 2 + 8)].map { $0 }, [1, 1, 0, 0, 0, 0, 1, 1])

        // Random 2-cell blocks are entirely on or entirely off in pairs.
        let pairs = try seedRow(id: "E126.pairs", start: .randomBlocks(seed: 126))
        for start in stride(from: 0, to: cols - 1, by: 2) {
            XCTAssertEqual(pairs[start], pairs[start + 1], "pair at \(start)")
        }

        let random = try seedRow(id: "E90.rand", start: .random(seed: 1, density: 0.05))
        XCTAssertTrue(random.contains(1))
    }

    /// The viewport only scrolls once a followed pattern's edge reaches the
    /// window boundary.
    func testFollowScrollsTheWindow() throws {
        guard GPUContext.isAvailable else { throw XCTSkip("no Metal 4 device") }
        let context = try GPUContext()
        let spec = Catalog.spec(id: "E28")!   // grows right at one column per step
        let board = Board(width: 1000, height: spec.board.height, start: .center)
        // The grid is tall enough that the sampling stride stays 1 over the run,
        // so this pins the follow, not the below-floor zoom-out.
        let simulation = try MetalSimulation(
            spec: spec, cols: 100, rows: 400, context: context, board: board)
        let start = simulation.viewportOrigin

        _ = try simulation.renderGPU(chunk: 40)
        XCTAssertEqual(simulation.viewportOrigin, start)

        _ = try simulation.renderGPU(chunk: 340)
        XCTAssertGreaterThan(simulation.viewportOrigin, start)
    }

    /// Zoom resizes the display grid (and so the viewport) without reseeding:
    /// in shrinks it, out grows it, and the grid matches the reported buffer.
    func testZoomResizesTheGridWithoutRestarting() throws {
        guard GPUContext.isAvailable else { throw XCTSkip("no Metal 4 device") }
        let context = try GPUContext()
        let spec = Catalog.spec(id: "E90")!
        // A centre seed stays visible across a zoom, so the run is provably not
        // restarting.
        let board = Board(width: 256, height: 16, start: .center)
        let simulation = try MetalSimulation(
            spec: spec, cols: 32, rows: 8, context: context, board: board,
            minimumZoom: 0.5)

        simulation.setZoom(2)
        XCTAssertEqual(simulation.zoom, 2)
        XCTAssertEqual(simulation.cols, 16)
        XCTAssertEqual(simulation.rows, 4)
        let zoomedIn = try simulation.renderGPU(chunk: 0)
        XCTAssertEqual(zoomedIn.cols, 16)
        XCTAssertEqual(zoomedIn.rows, 4)
        XCTAssertGreaterThan(nonZero(zoomedIn), 0, "the seed survives the zoom")

        simulation.setZoom(0.5)
        XCTAssertEqual(simulation.cols, 64)
        XCTAssertEqual(simulation.rows, 16)

        simulation.setZoom(100)
        XCTAssertEqual(simulation.zoom, ViewportGeometry.maximumZoom)
        XCTAssertEqual(simulation.cols, 8)
        XCTAssertEqual(simulation.rows, 2)
        // Below the display floor the zoom keeps falling while the grid stays
        // at the floor size; the fit samples the history at a coarser stride.
        simulation.setZoom(0.25)
        XCTAssertEqual(simulation.zoom, 0.25)
        XCTAssertEqual(simulation.cols, 64)
        XCTAssertEqual(simulation.rows, 16)
        simulation.setZoom(0.01)
        XCTAssertEqual(simulation.zoom, 0.01)
        XCTAssertEqual(simulation.cols, 64)
        XCTAssertEqual(simulation.rows, 16)
    }

    /// Below the display floor a display cell covers the block of source cells
    /// around it, and the fit gives that cell their average colour. A block that
    /// is half ink and half background lands between the two palette colours
    /// instead of voting for one of them, and a block the run has not reached is
    /// the page's own colour.
    func testToneAveragesTheBlockBelowTheFloor() throws {
        guard GPUContext.isAvailable else { throw XCTSkip("no Metal 4 device") }
        let context = try GPUContext()
        let spec = Catalog.spec(id: "E90")!
        let cols = 16
        let rows = 10
        let board = Board(width: 64, height: 16, start: .block([1]))
        let simulation = try MetalSimulation(
            spec: spec, cols: cols, rows: rows, context: context, board: board)

        let seed = try simulation.renderGPU(chunk: 0)
        XCTAssertEqual(seed.content, .paletteIndices, "one source cell per display cell is exact")

        // Eighteen rows over a nine-row span is a sampling stride of exactly two.
        // Rule 90 turns the full seed row into an empty one, so the top display
        // row covers one ink row and one background row and nothing else.
        _ = try simulation.renderGPU(chunk: 18)
        XCTAssertEqual(simulation.steppedRows, 18)
        let grid = try simulation.renderGPU(chunk: 0)
        XCTAssertEqual(grid.content, .colors)

        let palette = spec.display.palette
        let cells = colors(grid)
        let half = (palette[0].simd + palette[1].simd) / 2
        for column in 0..<cols {
            assertColor(
                cells[column], near: half,
                message: "the top row's blocks are half ink, so they keep the blend")
        }
        let untouched = cells[(rows - 1) * cols + cols / 2]
        assertColor(
            untouched, near: palette[0].simd,
            message: "a block past the run's rows is the page's colour")
    }

    /// The twin layout shares one horizon row and grows away from it in both
    /// directions. Each branch pins its newest row to its outer edge, and the
    /// pair is an exact vertical mirror around the horizon.
    func testTwinGrowsOutwardFromTheHorizon() throws {
        guard GPUContext.isAvailable else { throw XCTSkip("no Metal 4 device") }
        let context = try GPUContext()
        let spec = Catalog.spec(id: "E90")!
        let cols = 80
        let rows = 39
        let half = ViewportGeometry.twinHalfRows(rows: rows)
        let board = Board(width: 160, height: 16, start: .center)
        let simulation = try MetalSimulation(
            spec: spec, cols: cols, rows: rows, context: context, board: board,
            twin: true)
        XCTAssertEqual(simulation.twinHalfRows, half)

        let seed = values(try simulation.renderGPU(chunk: 0))
        for row in 0..<rows {
            let count = rowCount(seed, row: row, cols: cols)
            if row == half {
                XCTAssertEqual(count, 1, "the seed sits on the horizon row")
            } else {
                XCTAssertEqual(count, 0, "row \(row) stays background before growth")
            }
        }

        let grown = values(try simulation.renderGPU(chunk: 3))
        for distance in 0...half {
            for col in 0..<cols {
                XCTAssertEqual(
                    grown[(half - distance) * cols + col],
                    grown[(half + distance) * cols + col],
                    "row \(half - distance) mirrors row \(half + distance)")
            }
        }
        XCTAssertGreaterThan(
            rowCount(grown, row: half - 3, cols: cols), 1,
            "the newest row has grown past the seed")
        XCTAssertEqual(
            rowCount(grown, row: half - 4, cols: cols), 0,
            "rows the run has not reached stay background")
        XCTAssertEqual(rowCount(grown, row: 0, cols: cols), 0)
        XCTAssertEqual(
            rowCount(grown, row: half, cols: cols), 1,
            "the horizon still shows the seed row")
    }

    /// A zoom-out refits both branches of the twin layout: the horizon stays in
    /// the centre, the branches keep mirroring, and no row keeps stale cells.
    func testTwinRefitsOnZoom() throws {
        guard GPUContext.isAvailable else { throw XCTSkip("no Metal 4 device") }
        let context = try GPUContext()
        let spec = Catalog.spec(id: "E90")!
        let cols = 40
        let rows = 21
        let board = Board(width: 160, height: 16, start: .center)
        let simulation = try MetalSimulation(
            spec: spec, cols: cols, rows: rows, context: context, board: board,
            minimumZoom: 0.25, twin: true)
        _ = try simulation.renderGPU(chunk: 4)

        simulation.setZoom(0.5)
        let zoomed = values(try simulation.renderGPU(chunk: 0))
        let zoomedRows = simulation.rows
        let half = ViewportGeometry.twinHalfRows(rows: zoomedRows)
        XCTAssertEqual(zoomedRows, rows * 2 - 1)
        XCTAssertEqual(half, rows - 1)
        for distance in 0...half {
            for col in 0..<simulation.cols {
                XCTAssertEqual(
                    zoomed[(half - distance) * simulation.cols + col],
                    zoomed[(half + distance) * simulation.cols + col],
                    "row \(half - distance) mirrors after the zoom")
            }
        }
        XCTAssertEqual(
            rowCount(zoomed, row: half, cols: simulation.cols), 1,
            "the horizon row the growth started from survives the zoom")
        XCTAssertGreaterThan(
            rowCount(zoomed, row: half - 4, cols: simulation.cols), 1,
            "the latest row stays in view")
    }

    /// Past the display floor the fit samples the history at a coarser stride
    /// instead of dropping rows: the seed row stays on the horizon and the
    /// newest row on the outer edges, so the whole growth stays in view. The
    /// horizon keeps the seed row exactly, in the palette's ink colour.
    func testTwinKeepsTheSeedRowBelowTheDisplayFloor() throws {
        guard GPUContext.isAvailable else { throw XCTSkip("no Metal 4 device") }
        let context = try GPUContext()
        let spec = Catalog.spec(id: "E90")!
        let board = Board(width: 160, height: 16, start: .center)
        let simulation = try MetalSimulation(
            spec: spec, cols: 40, rows: 21, context: context, board: board,
            minimumZoom: 0.5, twin: true)
        simulation.setZoom(0.5)
        XCTAssertEqual(simulation.cols, 80)
        XCTAssertEqual(simulation.rows, 41)
        let half = ViewportGeometry.twinHalfRows(rows: simulation.rows)
        XCTAssertEqual(half, 20)

        // 60 steps is three times the rows a branch shows, so the fit must
        // sample every third source row to keep the seed. Growing to 160 then
        // makes the history ring reallocate and copy the older rows.
        _ = try simulation.renderGPU(chunk: 60)
        _ = try simulation.renderGPU(chunk: 100)
        XCTAssertEqual(simulation.steppedRows, 160)
        let grid = try simulation.renderGPU(chunk: 0)
        XCTAssertEqual(grid.content, .colors)

        let palette = spec.display.palette
        let cells = colors(grid)
        let horizon = (0..<simulation.cols).filter { column in
            !isColor(cells[half * simulation.cols + column], near: palette[0].simd)
        }
        XCTAssertEqual(
            horizon, [simulation.cols / 2],
            "the seed cell sits on the horizon at every stride")
        assertColor(
            cells[half * simulation.cols + simulation.cols / 2], near: palette[1].simd,
            message: "the horizon's seed cell is the ink colour")
    }

    private func values(_ grid: GPUColorGrid) -> [UInt8] {
        let cells = grid.buffer.contents().bindMemory(
            to: UInt8.self, capacity: grid.cols * grid.rows)
        return Array(UnsafeBufferPointer(start: cells, count: grid.cols * grid.rows))
    }

    /// A toned grid's cells, one normalised RGBA colour each.
    private func colors(_ grid: GPUColorGrid) -> [SIMD4<Float>] {
        let bytes = grid.buffer.contents().bindMemory(
            to: UInt8.self, capacity: grid.cols * grid.rows * 4)
        return (0..<(grid.cols * grid.rows)).map { cell in
            let offset = cell * 4
            return SIMD4<Float>(
                Float(bytes[offset]), Float(bytes[offset + 1]),
                Float(bytes[offset + 2]), Float(bytes[offset + 3])) / 255
        }
    }

    private func isColor(_ color: SIMD4<Float>, near expected: SIMD4<Float>) -> Bool {
        (0..<4).allSatisfy { abs(color[$0] - expected[$0]) <= 2.0 / 255 }
    }

    private func assertColor(
        _ color: SIMD4<Float>, near expected: SIMD4<Float>, message: String
    ) {
        for channel in 0..<4 {
            XCTAssertEqual(
                color[channel], expected[channel], accuracy: 2.0 / 255,
                "\(message) channel \(channel)")
        }
    }

    private func rowCount(_ cells: [UInt8], row: Int, cols: Int) -> Int {
        (0..<cols).reduce(0) { $0 + (cells[row * cols + $1] == 0 ? 0 : 1) }
    }
}
