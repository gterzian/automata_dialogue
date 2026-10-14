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
        let simulation = try MetalSimulation(
            spec: spec, cols: 100, rows: 10, context: context, board: board)
        let start = simulation.viewportOrigin

        _ = try simulation.renderGPU(chunk: 40)
        XCTAssertEqual(simulation.viewportOrigin, start)

        _ = try simulation.renderGPU(chunk: 300)
        XCTAssertGreaterThan(simulation.viewportOrigin, start)
    }
}
