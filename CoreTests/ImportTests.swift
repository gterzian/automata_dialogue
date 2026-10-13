import CoreGraphics
import ImageIO
import XCTest
@testable import Core

final class ImageImportTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RaterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    /// Writes a solid-color PNG of the given size.
    private func writeSourceImage(width: Int, height: Int, to url: URL) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func dimensions(of url: URL) throws -> (Int, Int) {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image.width, image.height)
    }

    func testNormalizeWritesSquarePNG() throws {
        let source = tempRoot.appendingPathComponent("source.png")
        try writeSourceImage(width: 800, height: 200, to: source)

        let directory = tempRoot.appendingPathComponent("session", isDirectory: true)
        let normalized = try ImageImport.normalize(source, into: directory)

        XCTAssertEqual(try dimensions(of: normalized).0, 512)
        XCTAssertEqual(try dimensions(of: normalized).1, 512)
        XCTAssertTrue(FileManager.default.fileExists(atPath: normalized.path))
    }

    func testNormalizeRejectsNonImage() throws {
        let text = tempRoot.appendingPathComponent("notes.txt")
        try "not an image".write(to: text, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try ImageImport.normalize(text, into: tempRoot))
    }

    func testNormalizeRejectsMissingFile() {
        let missing = tempRoot.appendingPathComponent("nope.png")
        XCTAssertThrowsError(try ImageImport.normalize(missing, into: tempRoot))
    }

    func testSessionDirectoryLayout() {
        let id = UUID()
        let directory = ImageImport.sessionDirectory(for: id)
        XCTAssertTrue(directory.path.contains("/Rater/"))
        XCTAssertEqual(directory.lastPathComponent, id.uuidString)
    }

    func testPurgeRemovesUnownedSessionFolders() throws {
        let kept = UUID()
        let stale = UUID()
        let fileManager = FileManager.default
        // A scoped root: purging the real `<tmp>/Rater` would delete the
        // session folder of a concurrently running rater-cli process.
        try fileManager.createDirectory(
            at: tempRoot.appendingPathComponent(kept.uuidString), withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: tempRoot.appendingPathComponent(stale.uuidString), withIntermediateDirectories: true)

        ImageImport.purgeStaleSessions(keeping: [kept], root: tempRoot, fileManager: fileManager)

        XCTAssertTrue(fileManager.fileExists(atPath: tempRoot.appendingPathComponent(kept.uuidString).path))
        XCTAssertFalse(fileManager.fileExists(atPath: tempRoot.appendingPathComponent(stale.uuidString).path))
    }
}
