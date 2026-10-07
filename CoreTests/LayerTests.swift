import Metal
import XCTest
@testable import Core

/// The `LayerRenderer` path is tested offscreen: the `runs` span compaction is
/// compared with a CPU run-length pass, and the render pass is read back from a
/// shared texture. The `CAMetalLayer`/display-link presentation itself needs a
/// screen and is not exercised here.
final class LayerTests: XCTestCase {
    private func makeGrid() -> ColorGrid {
        var grid = ColorGrid(cols: 5, rows: 3)
        // Row 0: 1 1 . 2 2   Row 1: . . . . .   Row 2: 2 . 2 2 .
        grid[0, 0] = 1; grid[1, 0] = 1; grid[3, 0] = 2; grid[4, 0] = 2
        grid[0, 2] = 2; grid[2, 2] = 2; grid[3, 2] = 2
        return grid
    }

    private func cpuSpans(_ grid: ColorGrid) -> [LayerRenderer.Span] {
        var spans: [LayerRenderer.Span] = []
        for row in 0..<grid.rows {
            var col = 0
            while col < grid.cols {
                let value = grid[col, row]
                guard value != 0 else {
                    col += 1
                    continue
                }
                var length = 1
                while col + length < grid.cols && grid[col + length, row] == value { length += 1 }
                spans.append(.init(row: UInt32(row), start: UInt32(col), length: UInt32(length), color: UInt32(value)))
                col += length
            }
        }
        return spans
    }

    func testSpanCompactionMatchesCPURuns() throws {
        guard GPUContext.isAvailable else { throw XCTSkip("no Metal 4 device") }
        let context = try GPUContext()
        let renderer = try LayerRenderer(context: context, pixelFormat: .bgra8Unorm)
        let grid = makeGrid()
        let gpu = try renderer.spans(for: grid).sorted {
            ($0.row, $0.start) < ($1.row, $1.start)
        }
        XCTAssertEqual(gpu, cpuSpans(grid))
    }

    /// The GPU-resident path compacts only the rows each frame adds; the
    /// accumulated spans must equal a full CPU compaction of the final grid.
    func testIncrementalSpansMatchFullCPUCompaction() throws {
        guard GPUContext.isAvailable else { throw XCTSkip("no Metal 4 device") }
        let context = try GPUContext()
        let spec = Catalog.spec(id: "E90")!
        let cols = spec.board.width
        let rows = 40
        let steps = 150
        let palette = spec.display.palette
        let renderer = try LayerRenderer(context: context, pixelFormat: .bgra8Unorm)
        let simulation = try MetalSimulation(spec: spec, cols: cols, rows: rows, steps: steps, context: context)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: cols, height: rows, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(context.device.makeTexture(descriptor: descriptor))

        var frames = 0
        while true {
            let gpu = try simulation.renderGPU(chunk: 7)
            try renderer.render(gpu: gpu, palette: palette, into: texture, wait: true)
            frames += 1
            if simulation.step >= simulation.totalSteps - 1 { break }
        }
        XCTAssertGreaterThan(frames, 1)

        let cpuGrid = CPUAutomatonRenderer().grid(spec: spec, cols: cols, rows: rows, steps: steps)
        let gpuSpans = renderer.accumulatedSpans().sorted { ($0.row, $0.start) < ($1.row, $1.start) }
        XCTAssertFalse(gpuSpans.isEmpty)
        XCTAssertEqual(gpuSpans, cpuSpans(cpuGrid))
    }

    func testRenderFillsSpansWithPaletteColours() throws {
        guard GPUContext.isAvailable else { throw XCTSkip("no Metal 4 device") }
        let context = try GPUContext()
        let renderer = try LayerRenderer(context: context, pixelFormat: .bgra8Unorm)
        let palette = Palette.standard(stateCount: 3)

        var grid = ColorGrid(cols: 4, rows: 2)
        for col in 0..<4 { grid[col, 0] = 1 } // one full run on the top row

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 4, height: 2, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = context.device.makeTexture(descriptor: descriptor) else {
            throw XCTSkip("could not create test texture")
        }
        try renderer.render(grid: grid, palette: palette, into: texture, wait: true)

        var bytes = [UInt8](repeating: 0, count: 4 * 2 * 4)
        bytes.withUnsafeMutableBytes { buffer in
            texture.getBytes(
                buffer.baseAddress!,
                bytesPerRow: 4 * 4,
                from: MTLRegionMake2D(0, 0, 4, 2),
                mipmapLevel: 0
            )
        }
        let ink = palette[1]
        let background = palette[0]
        assertPixel(bytes, x: 0, y: 0, bgra: ink, message: "top-left is ink")
        assertPixel(bytes, x: 3, y: 0, bgra: ink, message: "top-right is ink")
        assertPixel(bytes, x: 0, y: 1, bgra: background, message: "bottom is background")
        assertPixel(bytes, x: 3, y: 1, bgra: background, message: "bottom is background")
    }

    func testLayerSinkBuildsFromLayer() throws {
        guard GPUContext.isAvailable else { throw XCTSkip("no Metal 4 device") }
        let context = try GPUContext()
        let layer = CAMetalLayer()
        layer.pixelFormat = .bgra8Unorm
        let sink = try LayerSink(layer: layer, context: context)
        XCTAssertNotNil(layer.device)
        XCTAssertEqual(sink.clock.preferredFrameLatency, 2)
        XCTAssertNil(sink.errorDescription)
    }

    private func assertPixel(
        _ bytes: [UInt8],
        x: Int,
        y: Int,
        bgra color: PaletteColor,
        message: String
    ) {
        let offset = (y * 4 + x) * 4
        let expected: [Double] = [
            Double(color.b), Double(color.g), Double(color.r), Double(color.a)
        ]
        let actual = (0..<4).map { Double(bytes[offset + $0]) / 255.0 }
        for channel in 0..<4 {
            XCTAssertEqual(actual[channel], expected[channel], accuracy: 0.02, "\(message) channel \(channel)")
        }
    }
}
