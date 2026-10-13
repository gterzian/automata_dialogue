import Foundation

/// Totalistic CA, `colors` colors, radius 1, verbatim from the inventory.
///
/// The new color depends only on the sum `l + c + r` (0 … `3(k-1)`). The code
/// is a base-k number with `3(k-1) + 1` digits; digit `s` is the new color for
/// sum `s`. Codes divisible by 3 map sum 0 to color 0, so an empty background
/// stays empty — every `T` entry uses that property.
public struct TotalisticCA: RowProgram {
    public let width: Int
    public let colors: Int
    public let code: Int
    public var stateCount: Int { colors }
    /// Injected randomness (inventory §1.4); `nil` is a plain deterministic run.
    public let injection: RandomInjection?
    private var steps = 0
    private let table: [UInt8]
    private var cells: [UInt8]
    private var scratch: [UInt8]

    public init(code: Int, colors: Int = 3, width: Int, startColor: UInt8 = 1,
                injection: RandomInjection? = nil) {
        var row = [UInt8](repeating: 0, count: width)
        row[width / 2] = startColor
        self.init(code: code, colors: colors, width: width, row: row, injection: injection)
    }

    /// Builds from an explicit seed row, for board starts the single-cell start
    /// cannot express (seeds, blocks, random rows).
    public init(code: Int, colors: Int = 3, width: Int, row: [UInt8],
                injection: RandomInjection? = nil) {
        precondition(row.count == width, "seed row must match width")
        self.code = code
        self.colors = colors
        self.width = width
        self.injection = injection
        var t = [UInt8]()
        var rest = code
        for _ in 0..<(3 * (colors - 1) + 1) {
            t.append(UInt8(rest % colors))
            rest /= colors
        }
        table = t
        cells = row
        scratch = row
    }

    public mutating func step() {
        let width = self.width
        for i in 0..<width {
            let s = Int(cells[(i + width - 1) % width]) + Int(cells[i]) + Int(cells[(i + 1) % width])
            scratch[i] = table[s]
        }
        if let injection {
            steps &+= 1
            scratch[width / 2] = UInt8(
                SplitMix64.injectedValue(seed: injection.seed, step: UInt64(steps)) % UInt64(colors))
        }
        swap(&cells, &scratch)
    }

    public func row() -> [UInt8] { cells }
}
