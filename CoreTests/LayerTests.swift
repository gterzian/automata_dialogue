import Metal
import XCTest
@testable import Core

/// The `LayerRenderer` path is tested offscreen: a GPU-resident grid is
/// compacted into spans and drawn, and the render pass is read back from a
/// shared texture. The `CAMetalLayer`/display-link presentation itself needs a
/// screen and is not exercised here.
final class LayerTests: XCTestCase {
    func testRenderFillsSpansWithPaletteColours() throws {
        guard GPUContext.isAvailable else { throw XCTSkip("no Metal 4 device") }
        let context = try GPUContext()
        let renderer = try LayerRenderer(context: context, pixelFormat: .bgra8Unorm)
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
            palette: palette, into: texture, wait: true)

        let bytes = readTexture(texture)
        assertPixel(bytes, width: cols, x: 0, y: 0, bgra: palette[1], message: "top-left is ink")
        assertPixel(bytes, width: cols, x: 3, y: 0, bgra: palette[1], message: "top-right is ink")
        assertPixel(bytes, width: cols, x: 0, y: 1, bgra: palette[0], message: "bottom is background")
        assertPixel(bytes, width: cols, x: 3, y: 1, bgra: palette[0], message: "bottom is background")
    }

    func testLayerSinkBuildsFromLayer() throws {
        guard GPUContext.isAvailable else { throw XCTSkip("no Metal 4 device") }
        let context = try GPUContext()
        let layer = CAMetalLayer()
        layer.pixelFormat = .bgra8Unorm
        let sink = try LayerSink(layer: layer, context: context)
        XCTAssertNotNil(layer.device)
        XCTAssertEqual(sink.clock.preferredFrameLatency, 1)
        XCTAssertNil(sink.errorDescription)
    }

    /// The on-screen sink serializes frames: the simulation's color buffer and
    /// the layer's span/counter/uniform/palette buffers are shared across
    /// frames, so each frame must finish on the GPU before the CPU rewrites
    /// them. Distinct frames rendered back to back through the sink must each
    /// still show their own grid.
    func testLayerSinkSerializesFramesThatShareBuffers() throws {
        guard GPUContext.isAvailable else { throw XCTSkip("no Metal 4 device") }
        let context = try GPUContext()
        let layer = CAMetalLayer()
        layer.pixelFormat = .bgra8Unorm
        let sink = try LayerSink(layer: layer, context: context)
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
        for phase in 0..<4 {
            var grid = [UInt8](repeating: 0, count: cols * rows)
            for row in 0..<rows {
                let value = UInt8((row / 8 + phase) % 2)
                for col in 0..<cols { grid[row * cols + col] = value }
            }
            grids.append(grid)
        }

        var textures: [MTLTexture] = []
        for grid in grids {
            // The CPU rewrites the one shared cell buffer each frame, exactly as
            // the simulation's `fit` does in the live pipeline.
            grid.withUnsafeBufferPointer { source in
                _ = memcpy(cells.contents(), source.baseAddress!, source.count)
            }
            let frame = RenderFrame(
                specID: spec.id,
                gpu: GPUColorGrid(buffer: cells, cols: cols, rows: rows))
            let texture = try makeTexture()
            try sink.render(frame: frame, into: texture)
            textures.append(texture)
        }

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
