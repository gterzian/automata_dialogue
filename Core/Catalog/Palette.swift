import Foundation

/// The four behavior classes of the inventory, used by the catalog and the
/// system prompt.
public enum Behavior: String, Sendable, Hashable, CaseIterable, Codable {
    case repetition
    case nesting
    case randomness
    case complexity
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
}
