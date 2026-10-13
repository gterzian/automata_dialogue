import Foundation

/// SplitMix64, the PRNG used by the harness (`SPCore`). Deterministic across
/// platforms so the GPU kernels and the CPU references can be compared by hash.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        return Self.mix(state)
    }

    /// The random draw for injected randomness at `step` (1-based). It is the
    /// SplitMix64 mix of `seed + step × golden`, which the CPU reference and
    /// the GPU kernel can both compute from the step index alone, so they stay
    /// row-for-row identical without carrying the generator's state.
    public static func injectedValue(seed: UInt64, step: UInt64) -> UInt64 {
        mix(seed &+ step &* 0x9E37_79B9_7F4A_7C15)
    }

    private static func mix(_ value: UInt64) -> UInt64 {
        var z = value
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A one-dimensional cellular automaton advanced one row per `step()`.
///
/// Implementations are the *reference* for the GPU kernels: a test advances
/// both and compares row hashes. `stateCount` is the number of distinct cell
/// values (2 for elementary rules, 3 for 3-color totalistic rules).
public protocol RowProgram: Sendable {
    var width: Int { get }
    var stateCount: Int { get }
    mutating func step()
    func row() -> [UInt8]
}
