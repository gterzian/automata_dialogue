import XCTest
@testable import Core

/// The GPU `step`/`fit` kernels must reproduce the CPU `Core/Programs`
/// references exactly. Skipped when no Metal 4 device is present.
final class MetalTests: XCTestCase {
    func testGPUColorGridMatchesCPU() throws {
        guard GPUContext.isAvailable else {
            throw XCTSkip("no Metal 4 device")
        }
        let context = try GPUContext()
        let renderer = CPUAutomatonRenderer()
        let cases: [(id: String, cols: Int, rows: Int, steps: Int)] = [
            ("E90", 401, 200, 200),   // binary, native width
            ("E30", 401, 200, 200),   // binary, random-looking
            ("T1329", 161, 320, 320), // 3-color totalistic
            ("T177", 601, 300, 300),  // 3-color random
            ("E110", 400, 150, 400),  // right-pinned, board wider than display
        ]
        for testCase in cases {
            let spec = Catalog.spec(id: testCase.id)!
            let gpu = try MetalAutomaton.colorGrid(
                spec: spec,
                cols: testCase.cols,
                rows: testCase.rows,
                steps: testCase.steps,
                context: context
            )
            let cpu = renderer.grid(
                spec: spec,
                cols: testCase.cols,
                rows: testCase.rows,
                steps: testCase.steps
            )
            XCTAssertEqual(gpu, cpu, "GPU mismatch for \(testCase.id)")
        }
    }
}
