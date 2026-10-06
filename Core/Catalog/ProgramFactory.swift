import Foundation

/// Builds the CPU reference program for a `GPUProgram`/`Board` pair. Kept in
/// one place so the catalog's `reference` closures and tests agree.
public enum ProgramFactory {
    public static func make(gpu: GPUProgram, board: Board) -> any RowProgram {
        switch gpu {
        case .elementary(let rule):
            let start: ElementaryCA.Start
            switch board.start {
            case .center: start = .centerCell
            case .rightmost: start = .rightmostCell
            case .random(let seed): start = .random(seed: seed)
            }
            return ElementaryCA(rule: rule, width: board.width, start: start)
        case .totalistic(let code, let colors):
            return TotalisticCA(code: Int(code), colors: Int(colors), width: board.width)
        }
    }
}
