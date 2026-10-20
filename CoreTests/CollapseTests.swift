import Metal
import XCTest
@testable import Core

/// The intro sequence's timeline and its render path. Its appearance is
/// reviewed by hand; these tests pin the phase boundaries and the bounds the
/// renderer relies on.
final class CollapseTests: XCTestCase {
    /// The timeline clamps at its end and finishes on the horizon line the
    /// reveal starts from.
    func testTimelineRunsToItsEndOnTheHorizonLine() {
        let start = CollapseTimeline.frame(time: 0)
        XCTAssertEqual(start.dotOpacity, 0, accuracy: 0.001)
        XCTAssertGreaterThan(start.dotRadius, 0)
        XCTAssertEqual(start.endAlpha, 0, accuracy: 0.001)
        XCTAssertEqual(start.bloom, 0, accuracy: 0.001)
        XCTAssertEqual(start.collapse, 0, accuracy: 0.001)
        XCTAssertEqual(start.thinReveal, 0, accuracy: 0.001)
        XCTAssertEqual(start.frontEnergy, 0, accuracy: 0.001)
        XCTAssertEqual(start.lineSpring, 1, accuracy: 0.001)

        let whiteout = CollapseTimeline.frame(time: 4.8)
        XCTAssertTrue(whiteout.discs.contains { $0.radius > 1 })
        XCTAssertEqual(CollapseTimeline.frame(time: 5.6).fieldAlpha, 0, accuracy: 0.001)

        // A new ink point fades in, blooms to cover the frame, then collapses
        // into the horizon line and thins.
        let spot = CollapseTimeline.frame(time: 5.5)
        XCTAssertGreaterThan(spot.endAlpha, 0)
        XCTAssertLessThan(spot.endAlpha, 1)
        XCTAssertEqual(spot.collapse, 0, accuracy: 0.001)
        let black = CollapseTimeline.frame(time: 7.0)
        XCTAssertEqual(black.endAlpha, 1, accuracy: 0.001)
        XCTAssertEqual(black.bloom, 1, accuracy: 0.001)
        XCTAssertEqual(black.collapse, 0, accuracy: 0.001)
        let collapsing = CollapseTimeline.frame(time: 8.1)
        XCTAssertGreaterThan(collapsing.collapse, 0)
        XCTAssertLessThan(collapsing.collapse, 1)
        XCTAssertGreaterThan(collapsing.frontEnergy, 0)
        let rebound = CollapseTimeline.frame(time: 8.8)
        XCTAssertEqual(rebound.collapse, 1, accuracy: 0.001)
        XCTAssertGreaterThan(rebound.lineSpring, 1)

        let end = CollapseTimeline.frame(time: CollapseTimeline.duration)
        XCTAssertEqual(end.endAlpha, 1, accuracy: 0.001)
        XCTAssertEqual(end.bloom, 1, accuracy: 0.001)
        XCTAssertEqual(end.collapse, 1, accuracy: 0.001)
        XCTAssertEqual(end.thinReveal, 1, accuracy: 0.001)
        XCTAssertEqual(end.dotOpacity, 0, accuracy: 0.001)

        let frozen = CollapseTimeline.frame(time: CollapseTimeline.duration + 2)
        XCTAssertEqual(frozen.time, CollapseTimeline.duration)
        XCTAssertEqual(frozen.collapse, 1, accuracy: 0.001)
        XCTAssertEqual(frozen.thinReveal, 1, accuracy: 0.001)
    }

    /// The reveal's horizon row starts at the intro's hairline and reaches a
    /// full row over the handoff's duration.
    func testHorizonHandoffRampsFromHairlineToFullRow() {
        XCTAssertEqual(HorizonHandoff.reveal(elapsed: 0), 0, accuracy: 1e-6)
        XCTAssertEqual(HorizonHandoff.reveal(elapsed: -0.2), 0, accuracy: 1e-6)
        XCTAssertEqual(
            HorizonHandoff.reveal(elapsed: HorizonHandoff.duration), 1, accuracy: 1e-6)
        XCTAssertEqual(HorizonHandoff.reveal(elapsed: 5), 1, accuracy: 1e-6)
        var previous: Float = -1
        for step in 0...10 {
            let value = HorizonHandoff.reveal(
                elapsed: HorizonHandoff.duration * Double(step) / 10)
            XCTAssertGreaterThanOrEqual(value, previous)
            previous = value
        }
    }

    /// One seed always reproduces one run's look, and two seeds disagree in the
    /// geometry a viewer can tell apart.
    func testVariationIsReproducibleAndDiffers() {
        let first = CollapseVariation.seeded(11)
        let again = CollapseVariation.seeded(11)
        XCTAssertEqual(first.centerX, again.centerX)
        XCTAssertEqual(first.warp, again.warp)
        XCTAssertEqual(first.grainSeed, again.grainSeed)
        XCTAssertEqual(first.endSkew, again.endSkew)

        let other = CollapseVariation.seeded(12)
        XCTAssertNotEqual(first.centerX, other.centerX)
        XCTAssertNotEqual(first.grainSeed, other.grainSeed)
        XCTAssertNotEqual(first.endSkew, other.endSkew)
    }

    /// Every seed stays inside the bounds the renderer assumes, and still ends
    /// on the horizon line.
    func testEverySeedStaysInBoundsAndEndsOnTheLine() {
        for seed in UInt64(0)..<32 {
            let variation = CollapseVariation.seeded(seed)
            XCTAssertGreaterThan(variation.warp, 0)
            XCTAssertLessThan(variation.warp, 0.1)
            XCTAssertLessThanOrEqual(abs(variation.centerX), 0.03)
            XCTAssertLessThanOrEqual(abs(variation.centerY), 0.03)
            XCTAssertLessThanOrEqual(abs(variation.endSkew), 0.15)

            let middle = CollapseTimeline.frame(time: 3.0, variation: variation)
            XCTAssertLessThanOrEqual(middle.discs.count, CollapseTimeline.maxDiscs)
            XCTAssertGreaterThan(middle.dotRadius, 0)

            let end = CollapseTimeline.frame(
                time: CollapseTimeline.duration, variation: variation)
            XCTAssertEqual(end.endAlpha, 1, accuracy: 0.001)
            XCTAssertEqual(end.bloom, 1, accuracy: 0.001)
            XCTAssertEqual(end.collapse, 1, accuracy: 0.001)
            XCTAssertEqual(end.thinReveal, 1, accuracy: 0.001)
            XCTAssertEqual(end.dotOpacity, 0, accuracy: 0.001)
            XCTAssertGreaterThan(end.lineSpring, 0)
        }
    }

    /// Every phase reaches the renderer without a shader or uniform failure.
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
        for time in [Float(0.5), 3.0, 7.0, 9.0, 12.0, 14.0] {
            let frame = CollapseTimeline.frame(time: time)
            try renderer.render(
                into: texture, frame: frame, white: palette[0], ink: palette[1],
                lineHalfThickness: 0.0035)
        }
    }
}
