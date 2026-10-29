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

final class ReferenceLabelsTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RaterLabels-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func writeManifest(_ json: String) throws {
        try json.write(
            to: tempRoot.appendingPathComponent(ReferenceLabels.manifestName),
            atomically: true, encoding: .utf8)
    }

    private func makeImages(_ names: [String]) throws -> [String] {
        try names.map { name in
            let url = tempRoot.appendingPathComponent(name)
            try Data("{}".utf8).write(to: url)
            return url.path
        }
    }

    func testLabelsTheDrawingsTheManifestNames() throws {
        let paths = try makeImages(["first.png", "second.png"])
        try writeManifest(#"{"first.png": "nesting", "second.png": "randomness"}"#)

        let labels = try ReferenceLabels.load(forPaths: paths)

        XCTAssertEqual(labels[paths[0]], .nesting)
        XCTAssertEqual(labels[paths[1]], .randomness)
    }

    func testADirectoryWithoutAManifestHasNoLabels() throws {
        let paths = try makeImages(["plain.png"])
        XCTAssertTrue(try ReferenceLabels.load(forPaths: paths).isEmpty)
    }

    func testAMalformedManifestIsReported() throws {
        let paths = try makeImages(["example.png"])
        try writeManifest(#"{"example.png": "chaos"}"#)
        XCTAssertThrowsError(try ReferenceLabels.load(forPaths: paths))
    }

    /// `artifacts/examples.json` and the table in `artifacts/README.md` are two
    /// views of the reference set; nothing generates one from the other, so
    /// this fails when a drawing is added or reclassified on one side only.
    func testArtifactManifestMatchesTheReferenceTable() throws {
        let artifacts = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // CoreTests
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("artifacts")
        let readme = try String(
            contentsOf: artifacts.appendingPathComponent("README.md"), encoding: .utf8)
        var table: [String: Behavior] = [:]
        for line in readme.split(separator: "\n") {
            let cells = line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 3,
                  cells[1].hasPrefix("`example_"), cells[1].hasSuffix(".png`")
            else { continue }
            let name = String(cells[1].dropFirst().dropLast())
            table[name] = Behavior(rawValue: cells[2])
        }
        XCTAssertFalse(table.isEmpty, "artifact README has no reference table")

        let names = try FileManager.default
            .contentsOfDirectory(atPath: artifacts.path)
            .filter { $0.hasPrefix("example_") && $0.hasSuffix(".png") }
        let paths = names.map { artifacts.appendingPathComponent($0).path }
        let labels = try ReferenceLabels.load(forPaths: paths)

        XCTAssertEqual(labels.count, names.count, "a drawing is missing from the manifest")
        for name in names {
            XCTAssertEqual(
                labels[artifacts.appendingPathComponent(name).path], table[name],
                "\(name) is classified differently in the manifest and the README table")
        }
    }
}
