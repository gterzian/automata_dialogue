import CoreGraphics
import Foundation
import ImageIO

/// A decoded image as tightly packed RGBA8 pixels, row-major from the top-left.
/// The submission animation uploads it to a texture; the model path continues to
/// work from files and `CGImage`s.
public struct RasterImage: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let pixels: Data

    public init(width: Int, height: Int, pixels: Data) {
        precondition(width > 0 && height > 0, "raster size is positive")
        precondition(pixels.count == width * height * 4, "raster data matches its size")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// A texture upload needs an opaque colour space; an image's alpha is
    /// composited over `background`, the same page the image sits on.
    public init?(_ image: CGImage, background: PaletteColor = Palette.standard(stateCount: 2)[0]) {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0,
              let context = Self.makeContext(width: width, height: height) else {
            return nil
        }
        context.setFillColor(background.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let bytes = context.data else { return nil }
        // SAFETY: the context owns a width × height × 4 byte RGBA buffer that
        // stays alive until this initializer returns, and the copy is bounded by
        // that layout.
        self.init(
            width: width, height: height,
            pixels: Data(bytes: bytes, count: width * height * 4))
    }

    /// PNG data for the model's normalized input. ImageIO is not available on
    /// the GPU path, so the caller encodes here before the run starts.
    public func pngData() -> Data? {
        let info = Self.bitmapInfo
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: info),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              )
        else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, "public.png" as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    static var bitmapInfo: UInt32 {
        CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    }

    /// The one bitmap layout `RasterImage` reads back, shared with the drawing
    /// renderer so both sides agree on the byte order.
    static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo)
    }
}
