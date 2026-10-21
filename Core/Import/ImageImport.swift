import CoreGraphics
import Foundation
import ImageIO

public enum ImageImportError: Error, LocalizedError, Equatable {
    case unreadable(URL)
    case notAnImage(URL)
    case encodeFailed

    public var errorDescription: String? {
        switch self {
        case .unreadable(let url): "Could not read \(url.lastPathComponent)."
        case .notAnImage(let url): "\(url.lastPathComponent) is not a readable image."
        case .encodeFailed: "Could not encode the normalized image."
        }
    }
}

/// Loads an image file, normalizes it to the model's 512×512 input, and writes
/// it into the session's temp folder. Pure CoreGraphics + ImageIO so `Core`
/// stays AppKit-free.
public enum ImageImport {
    /// Default square side; the engine's `imageDimension` may override it.
    public static let modelDimension = 512

    /// `<tmp>/Rater/<session-id>/`
    public static func sessionDirectory(
        for sessionID: UUID,
        fileManager: FileManager = .default
    ) -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent("Rater", isDirectory: true)
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)
    }

    /// Decodes `source`, scales it (aspect-fit, centered on white) to a
    /// `dimension × dimension` square, and writes a PNG into `directory`.
    @discardableResult
    public static func normalize(
        _ source: URL,
        into directory: URL,
        dimension: Int = modelDimension,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil) else {
            throw ImageImportError.unreadable(source)
        }
        guard CGImageSourceGetCount(imageSource) > 0 else {
            throw ImageImportError.notAnImage(source)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: dimension,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            throw ImageImportError.unreadable(source)
        }

        guard let normalized = squareCanvas(thumbnail, dimension: dimension) else {
            throw ImageImportError.encodeFailed
        }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("drawing-\(UUID().uuidString).png")
        guard let encoded = CGImageDestinationCreateWithURL(
            destination as CFURL, "public.png" as CFString, 1, nil
        ) else {
            throw ImageImportError.encodeFailed
        }
        CGImageDestinationAddImage(encoded, normalized, nil)
        guard CGImageDestinationFinalize(encoded) else {
            throw ImageImportError.encodeFailed
        }
        return destination
    }

    /// Renders a freehand drawing at the model's square input size and writes
    /// it into the session folder. The drawing keeps the surface's dark page
    /// and light strokes; the prompt judges the drawn shapes, not the page.
    @discardableResult
    public static func normalize(
        _ drawing: Drawing,
        into directory: URL,
        dimension: Int = modelDimension,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let raster = DrawingImage.raster(drawing, width: dimension, height: dimension),
              let png = raster.pngData() else {
            throw ImageImportError.encodeFailed
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("drawing-\(UUID().uuidString).png")
        try png.write(to: destination, options: .atomic)
        return destination
    }

    /// Decodes `source` for the submission animation. The animation only needs
    /// a screen-sized texture, so a thumbnail bound keeps a large photograph
    /// from uploading at full resolution. The model input is normalized
    /// separately.
    public static func rasterImage(
        from source: URL,
        maximumDimension: Int = 2048
    ) throws -> RasterImage {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil) else {
            throw ImageImportError.unreadable(source)
        }
        guard CGImageSourceGetCount(imageSource) > 0 else {
            throw ImageImportError.notAnImage(source)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maximumDimension),
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary),
              let raster = RasterImage(thumbnail) else {
            throw ImageImportError.unreadable(source)
        }
        return raster
    }

    /// Aspect-fit `image` inside a white `dimension × dimension` canvas.
    static func squareCanvas(_ image: CGImage, dimension: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: dimension,
            height: dimension,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: dimension, height: dimension))

        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        guard width > 0, height > 0 else { return nil }
        let scale = min(CGFloat(dimension) / width, CGFloat(dimension) / height)
        let target = CGRect(
            x: (CGFloat(dimension) - width * scale) / 2,
            y: (CGFloat(dimension) - height * scale) / 2,
            width: width * scale,
            height: height * scale
        )
        context.interpolationQuality = .high
        context.draw(image, in: target)
        return context.makeImage()
    }

    /// Removes session folders at launch that no open session owns. `root`
    /// defaults to `<tmp>/Rater`; it is a parameter so the test suite can purge
    /// a scoped directory instead of deleting the live session folder of a
    /// concurrently running process.
    public static func purgeStaleSessions(
        keeping sessionIDs: Set<UUID>,
        root: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let root = root ?? fileManager.temporaryDirectory.appendingPathComponent("Rater", isDirectory: true)
        guard let children = try? fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil
        ) else { return }
        let keep = Set(sessionIDs.map(\.uuidString))
        for child in children where !keep.contains(child.lastPathComponent) {
            try? fileManager.removeItem(at: child)
        }
    }

    /// Removes one session's temp folder.
    public static func removeSessionDirectory(
        for sessionID: UUID,
        fileManager: FileManager = .default
    ) {
        try? fileManager.removeItem(at: sessionDirectory(for: sessionID, fileManager: fileManager))
    }
}
