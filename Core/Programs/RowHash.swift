import Foundation

/// Shared row hashing for golden tests and GPU/CPU comparison. FNV-1a 64 is
/// stable across platforms, so a recorded hash means the same thing on any
/// machine and in a shader readback.
public enum RowHash {
    public static func fnv1a(_ row: [UInt8]) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for cell in row {
            h ^= UInt64(cell)
            h = h &* 0x0000_0100_0000_01B3
        }
        return h
    }

    /// Advances a program `steps` times and returns the hash of the final row.
    public static func hash(of spec: ProgramSpec, steps: Int) -> UInt64 {
        var program = spec.makeProgram()
        for _ in 0..<steps { program.step() }
        return fnv1a(program.row())
    }
}
