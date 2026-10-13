import Foundation

/// Totalistic CA with next-nearest neighbors, 2 colors, radius 2, verbatim
/// from the inventory §1.3.
///
/// The new color depends only on the sum of the two cells on each side and the
/// cell itself, 0 … 5. The code is a 6-digit binary number; digit `s` from the
/// right is the new color for sum `s`. Code 20 is `010100`, so sums 2 and 4
/// give black and all other sums give white.
public struct K2R2CA: RowProgram {
    public let width: Int
    public let code: Int
    public var stateCount: Int { 2 }
    /// Injected randomness (inventory §1.4); `nil` is a plain deterministic run.
    public let injection: RandomInjection?
    private var steps = 0
    private let table: [UInt8]
    private var cells: [UInt8]
    private var scratch: [UInt8]

    public init(code: Int, width: Int, row: [UInt8], injection: RandomInjection? = nil) {
        precondition(row.count == width, "seed row must match width")
        self.code = code
        self.width = width
        self.injection = injection
        var t = [UInt8]()
        var rest = code
        for _ in 0..<6 {
            t.append(UInt8(rest & 1))
            rest >>= 1
        }
        table = t
        cells = row
        scratch = row
    }

    public mutating func step() {
        let width = self.width
        for i in 0..<width {
            let sum = Int(cells[(i + width - 2) % width])
                + Int(cells[(i + width - 1) % width])
                + Int(cells[i])
                + Int(cells[(i + 1) % width])
                + Int(cells[(i + 2) % width])
            scratch[i] = table[sum]
        }
        if let injection {
            steps &+= 1
            scratch[width / 2] = UInt8(
                SplitMix64.injectedValue(seed: injection.seed, step: UInt64(steps)) % 2)
        }
        swap(&cells, &scratch)
    }

    public func row() -> [UInt8] { cells }
}
