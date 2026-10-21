import Metal
import XCTest
@testable import Core

/// The intro's workflow contract: the cycle clamps on the frame the reveal
/// takes over from, the retraction reaches the renderer, and a seed reproduces
/// a run. The appearance itself is accepted by visual inspection.
final class CollapseTests: XCTestCase {
    /// The timeline clamps on the rest frame the reveal continues from.
    func testTimelineClampsOnTheRestFrame() {
        let rest = CollapseTimeline.frame(time: CollapseTimeline.duration)
        XCTAssertEqual(rest.time, CollapseTimeline.duration)
        XCTAssertEqual(rest.grow, .zero)
        XCTAssertEqual(rest.stretch, 1, accuracy: 1e-6)
        XCTAssertEqual(rest.endAlpha, 1, accuracy: 1e-6)
        XCTAssertEqual(rest.settle, 0, accuracy: 1e-6)

        let frozen = CollapseTimeline.frame(time: CollapseTimeline.duration + 2)
        XCTAssertEqual(frozen.time, CollapseTimeline.duration)
        XCTAssertEqual(frozen.grow, .zero)
        XCTAssertEqual(frozen.stretch, 1, accuracy: 1e-6)
    }

    /// The finale retracts the resting line onto the seed cell, and starts from
    /// exactly the frame the cycle froze on.
    func testRestFrameRetractsOntoTheSeedCell() {
        let rest = CollapseTimeline.rested(settle: 0, variation: .standard)
        let end = CollapseTimeline.frame(time: CollapseTimeline.duration)
        XCTAssertEqual(rest.stretch, end.stretch)
        XCTAssertEqual(rest.grow, end.grow)
        XCTAssertEqual(rest.grainSeed, end.grainSeed)
        XCTAssertEqual(rest.settle, 0, accuracy: 1e-6)

        let retracted = CollapseTimeline.rested(settle: 1, variation: .standard)
        XCTAssertEqual(retracted.settle, 1, accuracy: 1e-6)
        XCTAssertEqual(retracted.stretch, 1, accuracy: 1e-6)
        XCTAssertEqual(
            CollapseTimeline.rested(settle: 4, variation: .standard).settle, 1, accuracy: 1e-6)
        XCTAssertEqual(
            CollapseTimeline.rested(settle: -4, variation: .standard).settle, 0, accuracy: 1e-6)
    }

    /// One seed always reproduces one run, and two seeds differ.
    func testVariationIsReproducibleAndDiffers() {
        let first = CollapseVariation.seeded(11)
        let again = CollapseVariation.seeded(11)
        XCTAssertEqual(first.warmth, again.warmth)
        XCTAssertEqual(first.timeSkew, again.timeSkew)
        XCTAssertEqual(first.grainSeed, again.grainSeed)
        XCTAssertEqual(first.wobble, again.wobble)
        XCTAssertEqual(first.haloScale, again.haloScale)

        let other = CollapseVariation.seeded(12)
        XCTAssertNotEqual(first.warmth, other.warmth)
        XCTAssertNotEqual(first.grainSeed, other.grainSeed)
        XCTAssertNotEqual(first.timeSkew, other.timeSkew)
        XCTAssertNotEqual(first.wobble, other.wobble)
        XCTAssertNotEqual(first.haloScale, other.haloScale)
    }

    /// Every seed still rests on the handoff frame.
    func testEverySeedRestsOnTheHandoffFrame() {
        for seed in UInt64(0)..<32 {
            let variation = CollapseVariation.seeded(seed)
            let rest = CollapseTimeline.frame(
                time: CollapseTimeline.duration, variation: variation)
            XCTAssertEqual(rest.endAlpha, 1, accuracy: 0.001)
            XCTAssertEqual(rest.grow, .zero)
            XCTAssertEqual(rest.stretch, 1, accuracy: 1e-6)
        }
    }

    /// The submission beat parts the clones for its first phase, then collapses
    /// the doubled screen onto the intro's opening dot and clamps there.
    func testSubmissionTimelinePartsThenCollapses() {
        let start = SubmissionTimeline.frame(time: 0)
        XCTAssertEqual(start.doubling, 0, accuracy: 1e-6)
        XCTAssertEqual(start.collapse, 0, accuracy: 1e-6)

        let parted = SubmissionTimeline.frame(time: SubmissionTimeline.doublingDuration)
        XCTAssertEqual(parted.doubling, 1, accuracy: 1e-6)
        XCTAssertEqual(parted.collapse, 0, accuracy: 1e-6)

        let end = SubmissionTimeline.frame(time: SubmissionTimeline.duration)
        XCTAssertEqual(end.doubling, 1, accuracy: 1e-6)
        XCTAssertEqual(end.collapse, 1, accuracy: 1e-6)
        XCTAssertEqual(
            SubmissionTimeline.frame(time: SubmissionTimeline.duration + 10).collapse, 1,
            accuracy: 1e-6)
        XCTAssertEqual(SubmissionTimeline.frame(time: -4).time, 0)
    }

    /// The intro's opening frame is the dot the submission beat lands on: fully
    /// drawn, with the bloom not yet started, for every run's variation.
    func testIntroOpeningFrameIsTheSubmissionDot() {
        for seed in UInt64(0)..<32 {
            let opening = CollapseTimeline.frame(
                time: Float(ReviewIntro.openingTime),
                variation: CollapseVariation.seeded(seed))
            XCTAssertEqual(opening.endAlpha, 1, accuracy: 1e-6)
            XCTAssertEqual(opening.grow, .zero)
            XCTAssertEqual(opening.stretch, 0, accuracy: 1e-6)
            XCTAssertEqual(opening.settle, 0, accuracy: 1e-6)
        }
    }

    /// The render path accepts the cycle and the finale; the uniform layout must
    /// match the MSL struct.
    func testRendererDrawsEveryPhase() throws {
        guard GPUContext.isAvailable else { throw XCTSkip("no Metal 4 device") }
        let context = try GPUContext()
        let renderer = try CollapseRenderer(context: context, pixelFormat: .bgra8Unorm)
        let size = 256
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(context.device.makeTexture(descriptor: descriptor))
        let palette = Palette.standard(stateCount: 2)
        for time in [Float(0), CollapseTimeline.duration / 2, CollapseTimeline.duration] {
            let frame = CollapseTimeline.frame(time: time)
            try renderer.render(
                into: texture, frame: frame, white: palette[0], ink: palette[1],
                lineHalfThickness: 0.0035)
        }
        for settle in [Float(0), 0.5, 1] {
            let frame = CollapseTimeline.rested(settle: settle, variation: .standard)
            try renderer.render(
                into: texture, frame: frame, white: palette[0], ink: palette[1],
                lineHalfThickness: 0.0035)
        }
    }

    /// The submission shader compiles and its uniform layout matches the MSL
    /// struct across the beat's phases.
    func testSubmissionRendererDrawsEveryPhase() throws {
        guard GPUContext.isAvailable else { throw XCTSkip("no Metal 4 device") }
        let context = try GPUContext()
        let renderer = try SubmissionRenderer(context: context, pixelFormat: .bgra8Unorm)
        let image = RasterImage(
            width: 8, height: 8,
            pixels: Data((0..<(8 * 8 * 4)).map { UInt8($0 % 255) }))
        try renderer.setImage(image)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 256, height: 256, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(context.device.makeTexture(descriptor: descriptor))
        let palette = Palette.standard(stateCount: 2)
        for time in [
            Float(0),
            SubmissionTimeline.doublingDuration,
            (SubmissionTimeline.doublingDuration + SubmissionTimeline.duration) / 2,
            SubmissionTimeline.duration,
        ] {
            try renderer.render(
                into: texture, frame: SubmissionTimeline.frame(time: time),
                dotScale: 1, lineHalfThickness: 0.0035,
                white: palette[0], ink: palette[1])
        }
    }

    /// The beat's first frame is the submitted image, upright: the shader's
    /// texture orientation and aspect fit are a contract, not a look.
    func testSubmissionFirstFrameShowsTheImageUpright() throws {
        guard GPUContext.isAvailable else { throw XCTSkip("no Metal 4 device") }
        let context = try GPUContext()
        let renderer = try SubmissionRenderer(context: context, pixelFormat: .bgra8Unorm)
        let pixels: [UInt8] = [
            255, 0, 0, 255, 0, 255, 0, 255,
            0, 0, 255, 255, 255, 255, 255, 255,
        ]
        try renderer.setImage(RasterImage(width: 2, height: 2, pixels: Data(pixels)))

        let size = 64
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(context.device.makeTexture(descriptor: descriptor))
        let palette = Palette.standard(stateCount: 2)
        try renderer.render(
            into: texture, frame: SubmissionTimeline.frame(time: 0),
            dotScale: 1, lineHalfThickness: 0.0035,
            white: palette[0], ink: palette[1])

        let bytes = readTexture(texture)
        assertQuadrant(bytes, width: size, x: size / 8, y: size / 8, bgra: [0, 0, 1], "top-left red")
        assertQuadrant(
            bytes, width: size, x: size * 7 / 8, y: size / 8, bgra: [0, 1, 0], "top-right green")
        assertQuadrant(
            bytes, width: size, x: size / 8, y: size * 7 / 8, bgra: [1, 0, 0], "bottom-left blue")
        assertQuadrant(
            bytes, width: size, x: size * 7 / 8, y: size * 7 / 8, bgra: [1, 1, 1], "bottom-right white")
    }

    private func readTexture(_ texture: MTLTexture) -> [UInt8] {
        let bytesPerRow = texture.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * texture.height)
        bytes.withUnsafeMutableBytes { buffer in
            // SAFETY: the buffer is the texture's width × height × 4 byte
            // layout, which getBytes fills exactly.
            guard let base = buffer.baseAddress else { return }
            texture.getBytes(
                base,
                bytesPerRow: bytesPerRow,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0)
        }
        return bytes
    }

    private func assertQuadrant(
        _ bytes: [UInt8], width: Int, x: Int, y: Int, bgra expected: [Double], _ message: String
    ) {
        let offset = (y * width + x) * 4
        let actual = (0..<3).map { Double(bytes[offset + $0]) / 255 }
        for channel in 0..<3 {
            XCTAssertEqual(actual[channel], expected[channel], accuracy: 0.1, "\(message) channel \(channel)")
        }
    }
}
