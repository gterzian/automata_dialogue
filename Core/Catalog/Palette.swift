import CoreGraphics
import Foundation

/// The four behavior classes of the inventory, used by the catalog and the
/// system prompt.
public enum Behavior: String, Sendable, Hashable, CaseIterable, Codable {
    case repetition
    case nesting
    case randomness
    case complexity

    /// The name shown beside the English one in the review window, so the
    /// class the picture illustrates is legible to a Chinese-speaking user.
    public var chineseName: String {
        switch self {
        case .repetition: "重复"
        case .nesting: "嵌套"
        case .randomness: "随机"
        case .complexity: "复杂"
        }
    }
}

/// Up to 16 colors; index 0 is the background. Colors are
/// `float4`-shaped so the Metal `fit`/render path can upload the palette
/// unchanged.
public struct PaletteColor: Sendable, Hashable {
    public var r: Float
    public var g: Float
    public var b: Float
    public var a: Float

    public init(_ r: Float, _ g: Float, _ b: Float, _ a: Float = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public var simd: SIMD4<Float> { SIMD4(r, g, b, a) }

    /// The same colour in CoreGraphics' space, for the drawing surface.
    public var cgColor: CGColor {
        CGColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
    }
}

public struct Palette: Sendable, Hashable {
    public var colors: [PaletteColor]

    public init(colors: [PaletteColor]) {
        precondition(!colors.isEmpty && colors.count <= 16, "palette holds 1…16 colors")
        self.colors = colors
    }

    /// White / black for 2-color rules; white / gray / black for 3-color rules,
    /// per inventory §1.2. Index 0 is the background.
    public static func standard(stateCount: Int) -> Palette {
        switch stateCount {
        case 2:
            return Palette(colors: [
                PaletteColor(0.973, 0.969, 0.949), // background, warm white
                PaletteColor(0.078, 0.082, 0.098), // ink
            ])
        default:
            return Palette(colors: [
                PaletteColor(0.973, 0.969, 0.949), // background
                PaletteColor(0.549, 0.565, 0.600), // mid gray
                PaletteColor(0.078, 0.082, 0.098), // near black
            ])
        }
    }

    public subscript(index: Int) -> PaletteColor {
        colors[min(max(index, 0), colors.count - 1)]
    }

    public var count: Int { colors.count }

    /// The 16-entry `float4` table the Metal paths bind — the span draw's colours
    /// and the below-floor fit's block average — so both read one layout: one row
    /// per palette index, zero-filled past the last colour.
    public var table: [SIMD4<Float>] {
        var rows = [SIMD4<Float>](repeating: .zero, count: 16)
        for index in 0..<count { rows[index] = self[index].simd }
        return rows
    }
}
