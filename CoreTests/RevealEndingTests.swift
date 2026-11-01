import Metal
import XCTest
@testable import Core

/// The reveal's ending: the mask the driven run animates, and that both draw
/// paths apply it. The look of the fall itself is accepted by visual inspection.
final class RevealEndingTests: XCTestCase {
    /// The timeline starts on the untouched picture, keeps the speed the
    /// pull-back ended on, and settles on the single dot for the rest beat.
    func testTheCircleClosesIntoTheDot() {
        let variation = RevealVariation(wobble: 0.06, phase: 1.2, grain: 0.03)
        let collapse = Float(RevealEnding.collapseDuration)
        let total = Float(RevealEnding.duration)

        let start = RevealTimeline.frame(time: 0, variation: variation)
        XCTAssertEqual(start.mask.scale, 1, "the pull-back's last frame still shows the picture")
        XCTAssertEqual(start.mask.fall, 0)
        XCTAssertEqual(start.mask.wobble, 0, "the limb has not started eroding")
        XCTAssertEqual(start.mask.grain, 0, "the grain fades in with the ending")
        XCTAssertFalse(start.resting)

        let falling = RevealTimeline.frame(time: collapse / 2, variation: variation)
        XCTAssertEqual(falling.mask.fall, 0.75, accuracy: 1e-4)
        XCTAssertLessThan(falling.mask.scale, 1, "the picture has started to close")
        XCTAssertGreaterThan(falling.mask.scale, RevealTimeline.dotScale)
        XCTAssertGreaterThan(falling.mask.wobble, 0, "the limb erodes as the circle closes")

        let dot = RevealTimeline.frame(time: collapse, variation: variation)
        XCTAssertEqual(dot.mask.scale, RevealTimeline.dotScale, accuracy: 1e-6)
        XCTAssertEqual(dot.mask.fall, 1, accuracy: 1e-4)

        let rested = RevealTimeline.frame(time: total, variation: variation)
        XCTAssertTrue(rested.resting)
        XCTAssertEqual(rested.mask.scale, RevealTimeline.dotScale, accuracy: 1e-6)

        let later = RevealTimeline.frame(time: total + 10, variation: variation)
        XCTAssertEqual(later.mask, rested.mask, "the dot holds its last frame")
        XCTAssertTrue(later.resting)
    }

    /// The pull-back stops while the last rows still fly past at the per-tick
    /// cap, so the fall must continue at that speed: the first slice takes most
    /// of the picture and each later slice takes less as the fall settles into
    /// the dot. A fall that eases in reads as the animation braking.
    func testTheFallStartsFastAndSettlesIntoTheDot() {
        let variation = RevealVariation(wobble: 0.03, phase: 0.4, grain: 0.03)
        let collapse = Float(RevealEnding.collapseDuration)
        let quarter = collapse / 4

        let scale = (0..<5).map { step in
            RevealTimeline.frame(
                time: Float(step) * quarter, variation: variation
            ).mask.scale
        }
        let firstDrop = scale[0] - scale[1]
        let secondDrop = scale[1] - scale[2]
        let thirdDrop = scale[2] - scale[3]
        XCTAssertGreaterThan(firstDrop, secondDrop)
        XCTAssertGreaterThan(secondDrop, thirdDrop, "the fall settles as it closes")
        XCTAssertLessThan(scale[1], 0.75, "the fall leaves at speed, with no eased-in start")
        XCTAssertEqual(scale[4], RevealTimeline.dotScale, accuracy: 1e-6,
                       "the picture closes into the dot")
    }

    /// One seed always reproduces one ending, and two seeds differ.
    func testVariationIsReproducibleAndDiffers() {
        let first = RevealVariation.seeded(7)
        XCTAssertEqual(first, RevealVariation.seeded(7))
        let other = RevealVariation.seeded(8)
        XCTAssertNotEqual(first.wobble, other.wobble)
        XCTAssertNotEqual(first.phase, other.phase)
        XCTAssertNotEqual(first.grain, other.grain)
    }

    /// A toned grid — the below-floor picture the ending runs on — draws the
    /// page outside the falling limb and the sampled grid inside it.
    func testTheMaskHidesTonedCells() throws {
        guard GPUContext.isAvailable else { throw XCTSkip("no Metal 4 device") }
        let context = try GPUContext()
        let renderer = try ToneGridRenderer(context: context, pixelFormat: .bgra8Unorm)
        let cols = 8
        let rows = 4
        let cells = try XCTUnwrap(context.device.makeBuffer(
            length: cols * rows * 4, options: .storageModeShared))
        context.makeResident([cells])
        let bytes = cells.contents().bindMemory(to: UInt8.self, capacity: cols * rows * 4)
        for cell in 0..<(cols * rows) {
            bytes[cell * 4] = 255
            bytes[cell * 4 + 1] = 0
            bytes[cell * 4 + 2] = 0
            bytes[cell * 4 + 3] = 255
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: cols, height: rows, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(context.device.makeTexture(descriptor: descriptor))
        let background = Palette.standard(stateCount: 2)[0]
        let ink = Palette.standard(stateCount: 2)[1]

        try renderer.render(
            gpu: GPUColorGrid(buffer: cells, cols: cols, rows: rows, content: .colors),
            mask: RevealMask(scale: 0.35),
            background: background,
            ink: ink,
            into: texture)

        let drawn = readTexture(texture)
        assertNotBackground(drawn, width: cols, x: cols / 2, y: rows / 2, background, "kept centre")
        assertBackground(drawn, width: cols, x: 0, y: 0, background, "eaten corner")
    }

    /// The span path — the above-floor picture — drops a cell outside the
    /// falling limb, so the pass's page colour shows instead; a full mask keeps
    /// every cell.
    func testTheMaskHidesSpans() throws {
        guard GPUContext.isAvailable else { throw XCTSkip("no Metal 4 device") }
        let context = try GPUContext()
        let spec = Catalog.spec(id: "E90")!
        let renderer = try CellGridRenderer(context: context, pixelFormat: .bgra8Unorm)
        let cols = 8
        let rows = 4
        let cells = try XCTUnwrap(context.device.makeBuffer(
            length: cols * rows, options: .storageModeShared))
        context.makeResident([cells])
        let bytes = cells.contents().bindMemory(to: UInt8.self, capacity: cols * rows)
        for cell in 0..<(cols * rows) { bytes[cell] = 1 }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: cols, height: rows, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(context.device.makeTexture(descriptor: descriptor))
        let palette = spec.display.palette

        try renderer.render(
            gpu: GPUColorGrid(buffer: cells, cols: cols, rows: rows),
            palette: palette,
            into: texture)
        let full = readTexture(texture)
        assertNotBackground(full, width: cols, x: 0, y: 0, palette[0], "full mask keeps corners")

        try renderer.render(
            gpu: GPUColorGrid(buffer: cells, cols: cols, rows: rows),
            palette: palette,
            mask: RevealMask(scale: 0.35),
            into: texture)
        let drawn = readTexture(texture)
        assertNotBackground(drawn, width: cols, x: cols / 2, y: rows / 2, palette[0], "kept centre")
        assertBackground(drawn, width: cols, x: 0, y: 0, palette[0], "eaten corner")
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

    private func assertBackground(
        _ bytes: [UInt8], width: Int, x: Int, y: Int, _ colour: PaletteColor,
        _ message: String
    ) {
        XCTAssertTrue(isNear(bytes, width: width, x: x, y: y, colour), message)
    }

    private func assertNotBackground(
        _ bytes: [UInt8], width: Int, x: Int, y: Int, _ colour: PaletteColor,
        _ message: String
    ) {
        XCTAssertFalse(isNear(bytes, width: width, x: x, y: y, colour), message)
    }

    private func isNear(
        _ bytes: [UInt8], width: Int, x: Int, y: Int, _ colour: PaletteColor
    ) -> Bool {
        let offset = (y * width + x) * 4
        let channels: [(UInt8, Float)] = [
            (bytes[offset + 2], colour.r),
            (bytes[offset + 1], colour.g),
            (bytes[offset], colour.b),
        ]
        return channels.allSatisfy { abs(Float($0.0) / 255 - $0.1) < 0.05 }
    }
}
