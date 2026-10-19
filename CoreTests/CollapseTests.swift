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

    /// One seed always reproduces one run's look, and two seeds disagree in the
    /// geometry a viewer can tell apart.
    func testVariationIsReproducibleAndDiffers() {
        let first = CollapseVariation.seeded(11)
        let again = CollapseVariation.seeded(11)
        XCTAssertEqual(first.rayAngles, again.rayAngles)
        XCTAssertEqual(first.rayWidths, again.rayWidths)
        XCTAssertEqual(first.warp, again.warp)

        let other = CollapseVariation.seeded(12)
        XCTAssertNotEqual(first.rayAngles, other.rayAngles)
        XCTAssertNotEqual(first.centerX, other.centerX)
        XCTAssertNotEqual(first.grainSeed, other.grainSeed)
    }

    /// Every seed stays inside the buffers and the bounds the renderer assumes,
    /// and still ends on the bare white page.
    func testEverySeedStaysInBoundsAndEndsOnWhite() {
        for seed in UInt64(0)..<32 {
            let variation = CollapseVariation.seeded(seed)
            XCTAssertTrue((4...8).contains(variation.rayAngles.count))
            XCTAssertEqual(variation.rayAngles.count, variation.rayWidths.count)
            XCTAssertEqual(variation.rayAngles.count, variation.rayDarknesses.count)
            XCTAssertGreaterThan(variation.warp, 0)
            XCTAssertLessThan(variation.warp, 0.1)
            XCTAssertLessThanOrEqual(abs(variation.centerX), 0.03)
            XCTAssertLessThanOrEqual(abs(variation.centerY), 0.03)

            let middle = CollapseTimeline.frame(time: 7.5, variation: variation)
            XCTAssertLessThanOrEqual(middle.discs.count, CollapseTimeline.maxDiscs)
            XCTAssertLessThanOrEqual(middle.rays.count, CollapseTimeline.maxRays)
            XCTAssertGreaterThan(middle.dotRadius, 0)

            let end = CollapseTimeline.frame(
                time: CollapseTimeline.duration, variation: variation)
            XCTAssertEqual(end.shrinkRadius, 0, accuracy: 0.001)
            XCTAssertEqual(end.blackout, 1, accuracy: 0.001)
            XCTAssertEqual(end.dotOpacity, 0, accuracy: 0.001)
        }
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

    /// The opening point is a soft, uneven mound rather than a hard disc: its
    /// edge ramps over several pixels, and two seeds draw it differently.
    func testOpeningPointIsSoftAndUneven() throws {
        guard GPUContext.isAvailable else { throw XCTSkip("no Metal 4 device") }
        let context = try GPUContext()
        let renderer = try CollapseRenderer(context: context, pixelFormat: .bgra8Unorm)
        let size = 512
        let texture = try makeTexture(context, size: size)
        let palette = Palette.standard(stateCount: 2)
        let variation = CollapseVariation.seeded(5)

        let pixels = try renderPixels(
            renderer, into: texture, time: 0.5, size: size, variation: variation,
            white: palette[0], ink: palette[1])
        let background = Int(palette[0].b * 255)
        var darkest = (value: 255, index: 0)
        for index in stride(from: 0, to: pixels.count, by: 4) where Int(pixels[index]) < darkest.value {
            darkest = (Int(pixels[index]), index)
        }
        XCTAssertLessThan(darkest.value, 60, "the point must be drawn in ink")
        // Across the point's widest row, a hard anti-aliased edge jumps most of
        // the contrast between two pixels; a feathered mound spreads it out.
        var row = 0
        var width = 0
        for candidate in 0..<size {
            let count = (0..<size).reduce(0) { total, column in
                Int(pixels[(candidate * size + column) * 4]) < background - 40
                    ? total + 1 : total
            }
            if count > width {
                width = count
                row = candidate
            }
        }
        XCTAssertGreaterThan(width, 2, "the point must be big enough to measure")
        var largestStep = 0
        for column in 1..<size {
            let left = Int(pixels[(row * size + column - 1) * 4])
            let right = Int(pixels[(row * size + column) * 4])
            largestStep = max(largestStep, abs(right - left))
        }
        XCTAssertLessThan(
            largestStep, (background - darkest.value) * 2 / 3,
            "the point's edge must ramp, not step")

        let other = try renderPixels(
            renderer, into: texture, time: 0.5, size: size,
            variation: CollapseVariation.seeded(6), white: palette[0], ink: palette[1])
        XCTAssertNotEqual(pixels, other, "each seed must draw its own point")
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
        variation: CollapseVariation = .standard,
        white: PaletteColor,
        ink: PaletteColor
    ) throws -> [UInt8] {
        let frame = CollapseTimeline.frame(time: time, variation: variation)
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
