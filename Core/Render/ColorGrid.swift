import CoreGraphics
import Foundation

/// One palette index per display cell, row-major (design doc §5.4.1). Row 0 is
/// the seed row and rows increase downward in time.
public struct ColorGrid: Sendable, Hashable {
    public var cols: Int
    public var rows: Int
    public var cells: [UInt8]

    public init(cols: Int, rows: Int, cells: [UInt8]? = nil) {
        precondition(cols > 0 && rows > 0)
        self.cols = cols
        self.rows = rows
        self.cells = cells ?? [UInt8](repeating: 0, count: cols * rows)
        precondition(self.cells.count == cols * rows)
    }

    public subscript(col: Int, row: Int) -> UInt8 {
        get { cells[row * cols + col] }
        set { cells[row * cols + col] = newValue }
    }

    public var width: Int { cols }
    public var height: Int { rows }

    /// RGBA8 bytes for a `CGImage`/upload. `palette` maps indices to colors.
    public func rgbaBytes(palette: Palette) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: cols * rows * 4)
        var offset = 0
        for index in cells {
            let color = palette[Int(index)]
            data[offset] = UInt8(clamping: Int((color.r * 255).rounded()))
            data[offset + 1] = UInt8(clamping: Int((color.g * 255).rounded()))
            data[offset + 2] = UInt8(clamping: Int((color.b * 255).rounded()))
            data[offset + 3] = UInt8(clamping: Int((color.a * 255).rounded()))
            offset += 4
        }
        return data
    }

    public func cgImage(palette: Palette) -> CGImage? {
        let data = rgbaBytes(palette: palette)
        guard let provider = CGDataProvider(data: Data(data) as CFData) else { return nil }
        return CGImage(
            width: cols,
            height: rows,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: cols * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
