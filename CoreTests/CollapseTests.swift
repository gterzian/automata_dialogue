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
}
