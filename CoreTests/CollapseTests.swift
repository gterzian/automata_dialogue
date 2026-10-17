import Metal
import XCTest
@testable import Core

/// The intro sequence, tested through its pure timeline and offscreen draws.
/// The display-link presentation itself needs a screen and is not exercised
/// here.
final class CollapseTests: XCTestCase {
    /// The timeline is ten seconds, clamps after that, and ends with the black
    /// field fully shrunk away on the white page.
    func testTimelineRunsTenSecondsAndEndsOnWhite() {
        let start = CollapseTimeline.frame(time: 0)
        XCTAssertEqual(start.dotOpacity, 1, accuracy: 0.001)
        XCTAssertGreaterThan(start.dotRadius, 0)
        XCTAssertEqual(start.blackout, 0, accuracy: 0.001)
        XCTAssertEqual(start.shrinkMix, 0, accuracy: 0.001)

        let expanded = CollapseTimeline.frame(time: 5.0)
        XCTAssertTrue(expanded.discs.contains { $0.radius > 1 })

        let rays = CollapseTimeline.frame(time: 8.0)
        XCTAssertGreaterThan(rays.rays.count, 0)
        XCTAssertGreaterThan(CollapseTimeline.frame(time: 9.0).burstAlpha, 0)

        let end = CollapseTimeline.frame(time: CollapseTimeline.duration)
        XCTAssertEqual(end.blackout, 1, accuracy: 0.001)
        XCTAssertEqual(end.shrinkMix, 1, accuracy: 0.001)
        XCTAssertEqual(end.shrinkRadius, 0, accuracy: 0.001)
        XCTAssertEqual(end.dotOpacity, 0, accuracy: 0.001)

        let frozen = CollapseTimeline.frame(time: 12)
        XCTAssertEqual(frozen.time, CollapseTimeline.duration)
        XCTAssertEqual(frozen.shrinkRadius, 0, accuracy: 0.001)
    }

    /// The sequence draws dark discs and rays over the white page, and different
    /// times paint different frames.
    func testSequenceDrawsAndAdvances() throws {
        guard GPUContext.isAvailable else { throw XCTSkip("no Metal 4 device") }
        let context = try GPUContext()
        let renderer = try CollapseRenderer(context: context, pixelFormat: .bgra8Unorm)
        let size = 128
        let texture = try makeTexture(context, size: size)
        let palette = Palette.standard(stateCount: 2)

        let first = try renderPixels(
            renderer, into: texture, time: 3.0, size: size,
            white: palette[0], ink: palette[1])
        XCTAssertGreaterThan(darkPixels(first), 0, "the shaded disc must draw")
        let second = try renderPixels(
            renderer, into: texture, time: 7.5, size: size,
            white: palette[0], ink: palette[1])
        XCTAssertGreaterThan(darkPixels(second), 0, "the discs and rays must draw")
        XCTAssertNotEqual(first, second, "a different time must paint a different frame")
    }

    /// The ending is mostly black, then that black field shrinks into a white
    /// page with a final dark point that shrinks to nothing.
    func testEndShrinksToWhite() throws {
        guard GPUContext.isAvailable else { throw XCTSkip("no Metal 4 device") }
        let context = try GPUContext()
        let renderer = try CollapseRenderer(context: context, pixelFormat: .bgra8Unorm)
        let size = 128
        let texture = try makeTexture(context, size: size)
        let palette = Palette.standard(stateCount: 2)

        let black = try renderPixels(
            renderer, into: texture, time: 9.4, size: size,
            white: palette[0], ink: palette[1])
        XCTAssertGreaterThan(
            darkPixels(black), size * size * 9 / 10,
            "the starburst must go mostly black before the shrink")

        let largerDot = try renderPixels(
            renderer, into: texture, time: 9.75, size: size,
            white: palette[0], ink: palette[1])
        let smallerDot = try renderPixels(
            renderer, into: texture, time: 9.85, size: size,
            white: palette[0], ink: palette[1])
        XCTAssertGreaterThan(
            darkPixels(largerDot), darkPixels(smallerDot),
            "the dark point must shrink")
        XCTAssertGreaterThan(darkPixels(smallerDot), 0, "the point is still visible")

        let end = try renderPixels(
            renderer, into: texture, time: CollapseTimeline.duration, size: size,
            white: palette[0], ink: palette[1])
        XCTAssertEqual(darkPixels(end), 0, "the final frame is the bare white page")
        let centre = ((size / 2) * size + size / 2) * 4
        XCTAssertGreaterThan(
            end[centre + 2], 200, "the centre of the final frame is warm white")
    }

    private func darkPixels(_ pixels: [UInt8]) -> Int {
        var count = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            if pixels[index] < 100 && pixels[index + 1] < 100 && pixels[index + 2] < 100 {
                count += 1
            }
        }
        return count
    }

    private func makeTexture(_ context: GPUContext, size: Int) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        return try XCTUnwrap(context.device.makeTexture(descriptor: descriptor))
    }

    private func renderPixels(
        _ renderer: CollapseRenderer,
        into texture: MTLTexture,
        time: Float,
        size: Int,
        white: PaletteColor,
        ink: PaletteColor
    ) throws -> [UInt8] {
        let frame = CollapseTimeline.frame(time: time)
        try renderer.render(into: texture, frame: frame, white: white, ink: ink)
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
