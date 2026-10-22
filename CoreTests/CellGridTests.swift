import Metal
import XCTest
@testable import Core

/// The `CellGridRenderer` path is tested offscreen: a GPU-resident grid is
/// compacted into spans and drawn, and the render pass is read back from a
/// shared texture. A `CAMetalLayer` drawable needs a screen and is not
/// exercised here; the sink is driven through an `OffscreenTarget` instead.
final class CellGridTests: XCTestCase {
    func testRenderFillsSpansWithPaletteColours() throws {
        guard GPUContext.isAvailable else { throw XCTSkip("no Metal 4 device") }
        let context = try GPUContext()
        let renderer = try CellGridRenderer(context: context, pixelFormat: .bgra8Unorm)
        let palette = Palette.standard(stateCount: 3)
        let cols = 4
        let rows = 2

        let cells = try XCTUnwrap(
            context.device.makeBuffer(length: cols * rows, options: .storageModeShared))
        context.makeResident([cells])
        // One full ink run on the top row.
        var grid = [UInt8](repeating: 0, count: cols * rows)
        for col in 0..<cols { grid[col] = 1 }
        grid.withUnsafeBufferPointer { source in
            _ = memcpy(cells.contents(), source.baseAddress!, source.count)
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: cols, height: rows, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(context.device.makeTexture(descriptor: descriptor))
        try renderer.render(
            gpu: GPUColorGrid(buffer: cells, cols: cols, rows: rows),
            palette: palette, into: texture)

        let bytes = readTexture(texture)
        assertPixel(bytes, width: cols, x: 0, y: 0, bgra: palette[1], message: "top-left is ink")
        assertPixel(bytes, width: cols, x: 3, y: 0, bgra: palette[1], message: "top-right is ink")
        assertPixel(bytes, width: cols, x: 0, y: 1, bgra: palette[0], message: "bottom is background")
        assertPixel(bytes, width: cols, x: 3, y: 1, bgra: palette[0], message: "bottom is background")
    }

    /// Zoom resizes the grid while the color buffer stays put, so one renderer
    /// must handle a grid that grows (allocating spans) and then shrinks again
    /// (reusing them) against the same cells buffer.
    func testRendererHandlesGridResize() throws {
        guard GPUContext.isAvailable else { throw XCTSkip("no Metal 4 device") }
        let context = try GPUContext()
        let renderer = try CellGridRenderer(context: context, pixelFormat: .bgra8Unorm)
        let palette = Palette.standard(stateCount: 2)
        let maxCols = 16
        let maxRows = 8
        let cells = try XCTUnwrap(
            context.device.makeBuffer(length: maxCols * maxRows, options: .storageModeShared))
        context.makeResident([cells])

        func render(cols: Int, rows: Int) throws -> [UInt8] {
            var grid = [UInt8](repeating: 0, count: cols * rows)
            for col in 0..<cols { grid[col] = 1 }
            grid.withUnsafeBufferPointer { source in
                _ = memcpy(cells.contents(), source.baseAddress!, source.count)
            }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: cols, height: rows, mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .shared
            let texture = try XCTUnwrap(context.device.makeTexture(descriptor: descriptor))
            try renderer.render(
                gpu: GPUColorGrid(buffer: cells, cols: cols, rows: rows),
                palette: palette, into: texture)
            return readTexture(texture)
        }

        let small = try render(cols: 4, rows: 2)
        assertPixel(small, width: 4, x: 0, y: 0, bgra: palette[1], message: "small top ink")
        let large = try render(cols: 16, rows: 8)
        assertPixel(large, width: 16, x: 15, y: 0, bgra: palette[1], message: "large top ink")
        let smallAgain = try render(cols: 4, rows: 2)
        assertPixel(smallAgain, width: 4, x: 3, y: 1, bgra: palette[0], message: "small again row 1")
    }

    /// The sink draws into whatever target it is given, and the target's pixel
    /// format is the one the pipelines compile against.
    func testCellGridSinkBuildsFromTarget() throws {
        guard GPUContext.isAvailable else { throw XCTSkip("no Metal 4 device") }
        let context = try GPUContext()
        let layer = CAMetalLayer()
        layer.pixelFormat = .bgra8Unorm
        let target = MetalLayerTarget(layer: layer, displayLimits: .elements(columns: 64))
        let sink = try CellGridSink(target: target, context: context)
        XCTAssertNotNil(layer.device)
        XCTAssertEqual(sink.target.pixelFormat, .bgra8Unorm)
        XCTAssertEqual(sink.target.displayLimits.maximumColumns, 64)
        XCTAssertNil(sink.errorDescription)
        // A layer target has no surface until a display-link update supplies a
        // drawable, so a frame delivered before the first update draws nothing.
        XCTAssertNil(target.acquire())
    }

    /// The sink serializes frames: the simulation's color buffer and the
    /// renderer's span/counter/uniform/palette buffers are shared across
    /// frames, so each frame must finish on the GPU before the CPU rewrites
    /// them. Distinct frames rendered back to back through the sink must each
    /// still show their own grid.
    func testCellGridSinkSerializesFramesThatShareBuffers() throws {
        guard GPUContext.isAvailable else { throw XCTSkip("no Metal 4 device") }
        let context = try GPUContext()
        let spec = Catalog.spec(id: "E30")!
        let palette = spec.display.palette

        // Large enough that an unsynchronized frame's `runs` pass is still
        // reading the shared cells when the next frame overwrites them.
        let cols = 800
        let rows = 400
        let cells = try XCTUnwrap(
            context.device.makeBuffer(length: cols * rows, options: .storageModeShared))
        context.makeResident([cells])

        func makeTexture() throws -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: cols, height: rows, mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .shared
            return try XCTUnwrap(context.device.makeTexture(descriptor: descriptor))
        }

        // Four frames whose eight-row bands shift by a per-frame phase, so a
        // frame drawn from another frame's cells is easy to spot.
        var grids: [[UInt8]] = []
        var textures: [MTLTexture] = []
        for phase in 0..<4 {
            var grid = [UInt8](repeating: 0, count: cols * rows)
            for row in 0..<rows {
                let value = UInt8((row / 8 + phase) % 2)
                for col in 0..<cols { grid[row * cols + col] = value }
            }
            grids.append(grid)
            textures.append(try makeTexture())
        }

        // One sink over several surfaces, so every frame goes through the same
        // span, counter, uniform, and palette buffers.
        let sink = try CellGridSink(
            target: OffscreenTarget(textures: textures), context: context)
        for (grid, texture) in zip(grids, textures) {
            // The CPU rewrites the one shared cell buffer each frame, exactly as
            // the simulation's `fit` does in the live pipeline.
            grid.withUnsafeBufferPointer { source in
                _ = memcpy(cells.contents(), source.baseAddress!, source.count)
            }
            sink.deliver(RenderFrame(
                specID: spec.id,
                gpu: GPUColorGrid(buffer: cells, cols: cols, rows: rows)))
        }
        XCTAssertNil(sink.errorDescription)

        for (phase, (grid, texture)) in zip(grids, textures).enumerated() {
            let bytes = readTexture(texture)
            assertPixel(
                bytes, width: cols, x: 0, y: 0,
                bgra: palette[Int(grid[0])], message: "frame \(phase) top band")
            assertPixel(
                bytes, width: cols, x: 0, y: rows / 2,
                bgra: palette[Int(grid[(rows / 2) * cols])], message: "frame \(phase) middle band")
        }
    }

    private func readTexture(_ texture: MTLTexture) -> [UInt8] {
        let bytesPerRow = texture.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * texture.height)
        bytes.withUnsafeMutableBytes { buffer in
            texture.getBytes(
                buffer.baseAddress!,
                bytesPerRow: bytesPerRow,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }
        return bytes
    }

    private func assertPixel(
        _ bytes: [UInt8],
        width: Int,
        x: Int,
        y: Int,
        bgra color: PaletteColor,
        message: String
    ) {
        let offset = (y * width + x) * 4
        let expected: [Double] = [
            Double(color.b), Double(color.g), Double(color.r), Double(color.a)
        ]
        let actual = (0..<4).map { Double(bytes[offset + $0]) / 255.0 }
        for channel in 0..<4 {
            XCTAssertEqual(actual[channel], expected[channel], accuracy: 0.02, "\(message) channel \(channel)")
        }
    }
}
