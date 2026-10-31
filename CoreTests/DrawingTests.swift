import CoreGraphics
import ImageIO
import XCTest
@testable import Core

/// The drawing page's value path: strokes are collected without the view, and
/// a drawing becomes the raster the submission beat and the model consume.
/// Stroke colours and exact shapes are accepted by visual inspection.
final class DrawingTests: XCTestCase {
    func testStrokeLifecycleAndReset() {
        var drawing = Drawing(aspect: 2)
        XCTAssertTrue(drawing.isBlank)
        drawing.beginStroke(at: .init(x: 0.25, y: 0.5))
        drawing.extendStroke(to: .init(x: 0.75, y: 0.5))
        XCTAssertFalse(drawing.isBlank)
        XCTAssertEqual(drawing.strokes.count, 1)
        XCTAssertEqual(drawing.strokes[0].points.count, 2)

        drawing.reset(aspect: 1)
        XCTAssertTrue(drawing.isBlank)
        XCTAssertEqual(drawing.aspect, 1)
    }

    /// A blank drawing is a uniform page; a stroke makes some pixels differ.
    /// This pins that the stroke reaches the raster without pinning its look.
    func testRasterFollowsTheStrokes() throws {
        let blank = Drawing(aspect: 1)
        let blankImage = try XCTUnwrap(DrawingImage.raster(blank, width: 64, height: 64))
        XCTAssertTrue(uniform(blankImage))

        var drawn = Drawing(aspect: 1)
        drawn.beginStroke(at: .init(x: 0.2, y: 0.5))
        drawn.extendStroke(to: .init(x: 0.8, y: 0.5))
        let drawnImage = try XCTUnwrap(DrawingImage.raster(drawn, width: 64, height: 64))
        XCTAssertFalse(uniform(drawnImage))
    }

    /// The drawing is aspect-fit, so a wide surface into a square model input
    /// keeps its shapes instead of stretching them across the whole canvas.
    func testRasterAspectFitsTheDrawing() throws {
        var drawing = Drawing(aspect: 2)
        drawing.beginStroke(at: .init(x: 0, y: 0.5))
        drawing.extendStroke(to: .init(x: 1, y: 0.5))
        let raster = try XCTUnwrap(DrawingImage.raster(drawing, width: 80, height: 80))
        let background = pixel(raster, x: 40, y: 0)
        XCTAssertEqual(pixel(raster, x: 40, y: 79), background)
        XCTAssertNotEqual(pixel(raster, x: 40, y: 40), background)
    }

    /// The drawing's top-left origin survives the pixel order: a stroke in the
    /// top-left quadrant must not appear in the bottom-right.
    func testRasterKeepsTheTopLeftOrigin() throws {
        var drawing = Drawing(aspect: 1)
        drawing.beginStroke(at: .init(x: 0.1, y: 0.1))
        drawing.extendStroke(to: .init(x: 0.4, y: 0.4))
        let raster = try XCTUnwrap(DrawingImage.raster(drawing, width: 64, height: 64))
        let background = pixel(raster, x: 60, y: 60)
        XCTAssertNotEqual(pixel(raster, x: 16, y: 16), background)
        XCTAssertEqual(pixel(raster, x: 48, y: 48), background)
    }

    func testNormalizeDrawingWritesSquarePNG() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RaterDrawing-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var drawing = Drawing(aspect: 1.5)
        drawing.beginStroke(at: .init(x: 0.2, y: 0.2))
        drawing.extendStroke(to: .init(x: 0.8, y: 0.8))

        let normalized = try ImageImport.normalize(drawing, into: root, dimension: 256)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(normalized as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 256)
        XCTAssertEqual(image.height, 256)
    }

    func testRasterImagePNGRoundTrip() throws {
        var drawing = Drawing(aspect: 1)
        drawing.beginStroke(at: .init(x: 0.5, y: 0.5))
        let raster = try XCTUnwrap(DrawingImage.raster(drawing, width: 32, height: 32))
        // The window's thumbnail shows the same pixels through this image.
        let shown = try XCTUnwrap(raster.cgImage)
        XCTAssertEqual(shown.width, 32)
        XCTAssertEqual(shown.height, 32)
        let png = try XCTUnwrap(raster.pngData())
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let decoded = try XCTUnwrap(RasterImage(image))
        XCTAssertEqual(decoded.width, 32)
        XCTAssertEqual(decoded.height, 32)
    }

    private func uniform(_ raster: RasterImage) -> Bool {
        let bytes = Array(raster.pixels)
        let first = pixel(bytes, width: raster.width, x: 0, y: 0)
        for y in 0..<raster.height {
            for x in 0..<raster.width where pixel(bytes, width: raster.width, x: x, y: y) != first {
                return false
            }
        }
        return true
    }

    private func pixel(_ raster: RasterImage, x: Int, y: Int) -> UInt32 {
        pixel(Array(raster.pixels), width: raster.width, x: x, y: y)
    }

    private func pixel(_ bytes: [UInt8], width: Int, x: Int, y: Int) -> UInt32 {
        let offset = (y * width + x) * 4
        return UInt32(bytes[offset]) << 24
            | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8
            | UInt32(bytes[offset + 3])
    }
}
