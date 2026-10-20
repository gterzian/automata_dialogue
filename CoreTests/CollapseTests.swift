import Metal
import XCTest
@testable import Core

/// The intro sequence's timeline and its render path. Its appearance is
/// reviewed by hand; these tests pin the phase boundaries, the rest frame the
/// window freezes on, and the seed retraction the reveal continues from.
final class CollapseTests: XCTestCase {
    /// The cycle starts from the unlit dot, runs one burst, and rests on the
    /// horizon line.
    func testTimelineRunsOneCycleAndRests() {
        let start = CollapseTimeline.frame(time: 0)
        XCTAssertEqual(start.endAlpha, 0, accuracy: 0.001)
        XCTAssertEqual(start.bloom, 0, accuracy: 0.001)
        XCTAssertEqual(start.collapse, 0, accuracy: 0.001)
        XCTAssertEqual(start.settle, 0, accuracy: 0.001)
        XCTAssertEqual(start.frontEnergy, 0, accuracy: 0.001)
        XCTAssertEqual(start.lineSpring, 1, accuracy: 0.001)

        // The dot is lit before it bursts, and the burst covers the frame.
        let igniting = CollapseTimeline.frame(time: 0.3)
        XCTAssertEqual(igniting.endAlpha, 1, accuracy: 0.001)
        XCTAssertGreaterThan(igniting.bloom, 0)
        XCTAssertLessThan(igniting.bloom, 1)
        let covering = CollapseTimeline.frame(time: 1.0)
        XCTAssertLessThan(covering.bloom, 1)
        let covered = CollapseTimeline.frame(time: 1.4)
        XCTAssertEqual(covered.bloom, 1, accuracy: 0.001)
        XCTAssertEqual(covered.collapse, 0, accuracy: 0.001)

        // The mass then collapses into the line and rebounds.
        let collapsing = CollapseTimeline.frame(time: 1.7)
        XCTAssertGreaterThan(collapsing.collapse, 0)
        XCTAssertLessThan(collapsing.collapse, 1)
        XCTAssertGreaterThan(collapsing.frontEnergy, 0)
        let rebound = CollapseTimeline.frame(time: 2.1)
        XCTAssertEqual(rebound.collapse, 1, accuracy: 0.001)
        XCTAssertGreaterThan(rebound.lineSpring, 1)

        let rest = CollapseTimeline.frame(time: CollapseTimeline.duration)
        XCTAssertEqual(rest.endAlpha, 1, accuracy: 0.001)
        XCTAssertEqual(rest.bloom, 1, accuracy: 0.001)
        XCTAssertEqual(rest.collapse, 1, accuracy: 0.001)
        XCTAssertEqual(rest.settle, 0, accuracy: 0.001)
        XCTAssertEqual(rest.lineSpring, 1, accuracy: 1e-6)

        // The timeline clamps, so a frame past the end is the rest frame the
        // clock freezes on.
        let frozen = CollapseTimeline.frame(time: CollapseTimeline.duration + 2)
        XCTAssertEqual(frozen.time, CollapseTimeline.duration)
        XCTAssertEqual(frozen.collapse, 1, accuracy: 0.001)
        XCTAssertEqual(frozen.lineSpring, 1, accuracy: 1e-6)
    }

    /// The finale retracts the resting line onto the seed cell, and starts from
    /// exactly the frame the cycle froze on.
    func testRestFrameRetractsOntoTheSeedCell() {
        let rest = CollapseTimeline.rested(settle: 0, variation: .standard)
        let end = CollapseTimeline.frame(time: CollapseTimeline.duration)
        XCTAssertEqual(rest.collapse, end.collapse)
        XCTAssertEqual(rest.grainSeed, end.grainSeed)
        XCTAssertEqual(rest.settle, 0, accuracy: 1e-6)

        let retracted = CollapseTimeline.rested(settle: 1, variation: .standard)
        XCTAssertEqual(retracted.settle, 1, accuracy: 1e-6)
        XCTAssertEqual(retracted.lineSpring, 1, accuracy: 1e-6)
        XCTAssertEqual(
            CollapseTimeline.rested(settle: 4, variation: .standard).settle, 1, accuracy: 1e-6)
        XCTAssertEqual(
            CollapseTimeline.rested(settle: -4, variation: .standard).settle, 0, accuracy: 1e-6)
    }

    /// One seed always reproduces one run's look, and two seeds disagree in the
    /// geometry a viewer can tell apart.
    func testVariationIsReproducibleAndDiffers() {
        let first = CollapseVariation.seeded(11)
        let again = CollapseVariation.seeded(11)
        XCTAssertEqual(first.centerX, again.centerX)
        XCTAssertEqual(first.timeSkew, again.timeSkew)
        XCTAssertEqual(first.grainSeed, again.grainSeed)

        let other = CollapseVariation.seeded(12)
        XCTAssertNotEqual(first.centerX, other.centerX)
        XCTAssertNotEqual(first.grainSeed, other.grainSeed)
        XCTAssertNotEqual(first.timeSkew, other.timeSkew)
    }

    /// Every seed stays inside the bounds the renderer assumes, and still rests
    /// on the line.
    func testEverySeedStaysInBoundsAndRestsOnTheLine() {
        for seed in UInt64(0)..<32 {
            let variation = CollapseVariation.seeded(seed)
            XCTAssertLessThanOrEqual(abs(variation.timeSkew), 0.1)
            XCTAssertLessThanOrEqual(abs(variation.centerX), 0.03)
            XCTAssertLessThanOrEqual(abs(variation.centerY), 0.03)

            let middle = CollapseTimeline.frame(time: 0.8, variation: variation)
            XCTAssertGreaterThan(middle.bloom, 0)
            XCTAssertLessThan(middle.bloom, 1)

            // A leading or lagging run is clamped, so it still rests on exactly
            // the frame the reveal continues from.
            let rest = CollapseTimeline.frame(
                time: CollapseTimeline.duration, variation: variation)
            XCTAssertEqual(rest.endAlpha, 1, accuracy: 0.001)
            XCTAssertEqual(rest.bloom, 1, accuracy: 0.001)
            XCTAssertEqual(rest.collapse, 1, accuracy: 0.001)
            XCTAssertEqual(rest.lineSpring, 1, accuracy: 1e-6)
        }
    }

    /// Every phase, including the finale, reaches the renderer without a shader
    /// or uniform failure; the uniform layout must match the MSL struct.
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
        for time in [Float(0.1), 0.5, 1.4, 1.7, 2.1, 3.0, 4.0] {
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
