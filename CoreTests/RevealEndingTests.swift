import Metal
import XCTest
@testable import Core

/// The reveal's ending: the mask the driven run animates, and that both draw
/// paths apply it. The look of the wipe itself is accepted by visual inspection.
final class RevealEndingTests: XCTestCase {
    /// The mask starts on the untouched picture, eats it back to the horizon
    /// line, closes the line into its centre point, and rests there.
    func testMaskEatsThePictureBackToItsPoint() {
        let variation = RevealVariation(wobble: 0.04, phase: 1.2, lag: 0.1)
        let rows = 400
        let cols = 720
        let wipe = Float(RevealEnding.wipeDuration)
        let line = Float(RevealEnding.lineDuration)

        let start = RevealTimeline.frame(
            time: 0, rows: rows, cols: cols, variation: variation)
        XCTAssertEqual(start.mask.left, 0, "the ended pull-back still shows the whole picture")
        XCTAssertEqual(start.mask.top, 0)
        XCTAssertEqual(start.mask.right, 1)
        XCTAssertEqual(start.mask.bottom, 1)
        XCTAssertEqual(start.mask.wobble, 0, "the edge has not started wandering")
        XCTAssertFalse(start.resting)

        let wiping = RevealTimeline.frame(
            time: wipe / 2, rows: rows, cols: cols, variation: variation)
        XCTAssertGreaterThan(wiping.mask.top, 0, "the top edge has eaten into the picture")
        XCTAssertLessThan(wiping.mask.bottom, 1)
        XCTAssertGreaterThan(wiping.mask.wobble, 0, "the edge wanders while it eats")
        XCTAssertEqual(wiping.mask.left, 0, accuracy: 1e-6)
        XCTAssertEqual(wiping.mask.right, 1, accuracy: 1e-6)

        let horizon = RevealTimeline.frame(
            time: wipe, rows: rows, cols: cols, variation: variation)
        let lineHalf = RevealTimeline.lineRows / Float(rows) / 2
        XCTAssertEqual(horizon.mask.top, 0.5 - lineHalf, accuracy: 1e-4)
        XCTAssertEqual(horizon.mask.bottom, 0.5 + lineHalf, accuracy: 1e-4)
        XCTAssertEqual(horizon.mask.left, 0, accuracy: 1e-6)
        XCTAssertEqual(horizon.mask.right, 1, accuracy: 1e-6)
        XCTAssertFalse(horizon.resting)

        let point = RevealTimeline.frame(
            time: wipe + line, rows: rows, cols: cols, variation: variation)
        let pointHalf = RevealTimeline.lineRows / Float(cols) / 2
        XCTAssertEqual(point.mask.left, 0.5 - pointHalf, accuracy: 1e-4)
        XCTAssertEqual(point.mask.right, 0.5 + pointHalf, accuracy: 1e-4)
        XCTAssertEqual(point.mask.top, 0.5 - lineHalf, accuracy: 1e-4)
        XCTAssertFalse(point.resting, "the point holds for its rest beat")

        let rested = RevealTimeline.frame(
            time: Float(RevealEnding.duration) + 10, rows: rows, cols: cols,
            variation: variation)
        XCTAssertTrue(rested.resting)
        XCTAssertEqual(rested.mask, point.mask, "the point holds its last frame")
    }

    /// The upper edge leads and the lower one trails by the run's lag, so the
    /// picture is eaten from the top down.
    func testUpperEdgeLeadsTheLowerOne() {
        let variation = RevealVariation(wobble: 0.03, phase: 0.4, lag: 0.15)
        let frame = RevealTimeline.frame(
            time: 0.12, rows: 200, cols: 300, variation: variation)
        XCTAssertGreaterThan(frame.mask.top, 0, "the top edge has started")
        XCTAssertEqual(frame.mask.bottom, 1, accuracy: 1e-6, "the bottom edge waits")
    }

    /// One seed always reproduces one ending, and two seeds differ.
    func testVariationIsReproducibleAndDiffers() {
        let first = RevealVariation.seeded(7)
        XCTAssertEqual(first, RevealVariation.seeded(7))
        let other = RevealVariation.seeded(8)
        XCTAssertNotEqual(first.wobble, other.wobble)
        XCTAssertNotEqual(first.phase, other.phase)
        XCTAssertNotEqual(first.lag, other.lag)
    }

    /// A toned grid — the below-floor picture the ending runs on — draws the
    /// page where the mask hides it and the grid where it does not.
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

        try renderer.render(
            gpu: GPUColorGrid(buffer: cells, cols: cols, rows: rows, content: .colors),
            mask: RevealMask(left: 0, top: 0.5, right: 1, bottom: 1, wobble: 0, phase: 0),
            background: background,
            into: texture)

        let drawn = readTexture(texture)
        assertBackground(drawn, width: cols, x: 2, y: 1, background, "eaten top")
        assertNotBackground(drawn, width: cols, x: 2, y: 2, background, "kept bottom")
    }

    /// The span path — the above-floor picture — drops a masked cell, so the
    /// pass's page colour shows instead.
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
            mask: RevealMask(left: 0, top: 0, right: 1, bottom: 0.5, wobble: 0, phase: 0),
            into: texture)

        let drawn = readTexture(texture)
        assertNotBackground(drawn, width: cols, x: 2, y: 1, palette[0], "kept top")
        assertBackground(drawn, width: cols, x: 2, y: 2, palette[0], "eaten bottom")
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
