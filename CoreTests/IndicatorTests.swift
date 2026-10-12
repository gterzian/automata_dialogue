import Metal
import XCTest
@testable import Core

/// The "working" indicator's Metal draw, tested offscreen. The display-link
/// presentation itself needs a screen and is not exercised here.
final class IndicatorTests: XCTestCase {
    /// The rings must cover some pixels that are not the background, and a
    /// different `time` must paint a different frame (the animation advances).
    func testRingsDrawAndAdvance() throws {
        guard GPUContext.isAvailable else { throw XCTSkip("no Metal 4 device") }
        let context = try GPUContext()
        let renderer = try IndicatorRenderer(context: context, pixelFormat: .bgra8Unorm)

        let size = 64
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(context.device.makeTexture(descriptor: descriptor))

        let background = PaletteColor(0.07, 0.08, 0.10)
        let ink = PaletteColor(0.973, 0.969, 0.949)

        let first = try renderPixels(renderer, into: texture, time: 0.25, size: size, background: background, ink: ink)
        XCTAssertTrue(
            first.contains { $0 > 128 },
            "the animation must draw something over the background"
        )
        let second = try renderPixels(renderer, into: texture, time: 0.6, size: size, background: background, ink: ink)
        XCTAssertNotEqual(first, second, "a different time must paint a different frame")
    }

    private func renderPixels(
        _ renderer: IndicatorRenderer,
        into texture: MTLTexture,
        time: Float,
        size: Int,
        background: PaletteColor,
        ink: PaletteColor
    ) throws -> [UInt8] {
        try renderer.render(
            into: texture, time: time, background: background, ink: ink, wait: true)
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        bytes.withUnsafeMutableBytes { buffer in
            texture.getBytes(
                buffer.baseAddress!,
                bytesPerRow: size * 4,
                from: MTLRegionMake2D(0, 0, size, size),
                mipmapLevel: 0
            )
        }
        return bytes
    }
}
