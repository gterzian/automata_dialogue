import Foundation

/// Elementary cellular automaton (Wolfram code), verbatim from the inventory.
///
/// The neighborhood `(l, c, r)` is read as `4l + 2c + r`; the new cell is that
/// bit of `rule`. Edges wrap, which suits a board wider than the pattern
/// (`width >= 2 * steps + 1` for a single-cell start).
public struct ElementaryCA: RowProgram {
    public enum Start: Sendable, Hashable {
        case centerCell
        case rightmostCell
        case random(seed: UInt64)
    }

    public let width: Int
    public let rule: UInt8
    public var stateCount: Int { 2 }
    /// Injected randomness (inventory §1.4); `nil` is a plain deterministic run.
    public let injection: RandomInjection?
    private var steps = 0
    private var cells: [UInt8]
    private var scratch: [UInt8]

    public init(rule: UInt8, width: Int, start: Start, injection: RandomInjection? = nil) {
        self.rule = rule
        self.width = width
        self.injection = injection
        var row = [UInt8](repeating: 0, count: width)
        switch start {
        case .centerCell: row[width / 2] = 1
        case .rightmostCell: row[width - 1] = 1
        case .random(let seed):
            var rng = SplitMix64(seed: seed)
            for i in 0..<width { row[i] = UInt8(rng.next() & 1) }
        }
        cells = row
        scratch = row
    }

    /// Builds from an explicit seed row, for board starts the typed `Start`
    /// cannot express (seeds, blocks, non-half densities).
    public init(rule: UInt8, width: Int, row: [UInt8], injection: RandomInjection? = nil) {
        precondition(row.count == width, "seed row must match width")
        self.rule = rule
        self.width = width
        self.injection = injection
        cells = row
        scratch = row
    }

    public mutating func step() {
        let rule = self.rule
        let width = self.width
        for i in 0..<width {
            let l = cells[(i + width - 1) % width]
            let c = cells[i]
            let r = cells[(i + 1) % width]
            scratch[i] = (rule >> ((l << 2) | (c << 1) | r)) & 1
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
