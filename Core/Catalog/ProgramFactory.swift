import Foundation

/// Builds the CPU reference program for a `GPUProgram`/`Board` pair. Kept in
/// one place so the catalog's `reference` closures and tests agree.
public enum ProgramFactory {
    public static func make(gpu: GPUProgram, board: Board) -> any RowProgram {
        switch gpu {
        case .elementary(let rule):
            return ElementaryCA(
                rule: rule, width: board.width,
                row: initialRow(board.start, width: board.width, colors: 2),
                injection: board.injection)
        case .totalistic(let code, let colors):
            return TotalisticCA(
                code: Int(code), colors: Int(colors), width: board.width,
                row: initialRow(board.start, width: board.width, colors: Int(colors)),
                injection: board.injection)
        case .k2r2(let code):
            return K2R2CA(
                code: Int(code), width: board.width,
                row: initialRow(board.start, width: board.width, colors: 2),
                injection: board.injection)
        }
    }

    /// The seed row for a board start (inventory §1.4). Deterministic: the
    /// golden hashes depend on the exact `SplitMix64` draw order, so
    /// density-one-half random rows keep the original `next() & 1` draw. A
    /// 3-color random row draws each of white, gray and black with probability
    /// one third, so it ignores `density`.
    static func initialRow(_ start: BoardStart, width: Int, colors: Int) -> [UInt8] {
        var row = [UInt8](repeating: 0, count: width)
        switch start {
        case .center:
            row[width / 2] = 1
        case .rightmost:
            row[width - 1] = 1
        case .random(let seed, let density):
            var rng = SplitMix64(seed: seed)
            if colors == 3 {
                // The inventory draws white, gray and black with probability
                // one third each from a 3-color random row (§1.4).
                for i in 0..<width { row[i] = UInt8(rng.next() % 3) }
            } else if density == 0.5 {
                for i in 0..<width { row[i] = UInt8(rng.next() & 1) }
            } else {
                let scale = 1.0 / 9_007_199_254_740_992.0 // 2^53
                for i in 0..<width {
                    row[i] = Double(rng.next() >> 11) * scale < density ? 1 : 0
                }
            }
        case .randomBlocks(let seed):
            var rng = SplitMix64(seed: seed)
            var i = 0
            while i < width {
                let on: UInt8 = (rng.next() & 1) == 1 ? 1 : 0
                row[i] = on
                if i + 1 < width { row[i + 1] = on }
                i += 2
            }
        case .block(let block):
            precondition(!block.isEmpty, "repeated block must not be empty")
            for i in 0..<width { row[i] = block[i % block.count] }
        case .seed(let number, let colors):
            var digits: [UInt8] = []
            var n = number
            repeat {
                digits.append(UInt8(n % colors))
                n /= colors
            } while n > 0
            digits.reverse()
            let origin = width / 2
            for (offset, digit) in digits.enumerated() where origin + offset < width {
                row[origin + offset] = digit
            }
        }
        return row
    }
}
