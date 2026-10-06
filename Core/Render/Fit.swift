import Foundation

/// Maps a board row onto the display columns.
///
/// When the board is wider than the display, each display column covers a
/// block of source cells (majority vote). When the board is narrower, it is
/// placed inside the display (centered, or flush right for `pinRight`) with the
/// remaining cells left as background. Source indices are clamped to the board:
/// a display column that reaches past the board reads background, never the
/// wrapped left edge.
public struct Fit: Sendable, Hashable {
    public let block: Int
    public let boardWidth: Int
    public let displayCols: Int
    /// First source cell shown when the board is wider than the display.
    public let sourceOrigin: Int
    /// Display columns of left padding when the board fits inside the display.
    public let padLeft: Int

    public init(boardWidth: Int, displayCols: Int, pinRight: Bool) {
        let cols = max(1, displayCols)
        self.boardWidth = boardWidth
        self.displayCols = cols
        if boardWidth >= cols {
            if pinRight {
                let block = max(1, boardWidth / cols)
                self.block = block
                self.sourceOrigin = boardWidth - cols * block
                self.padLeft = 0
            } else {
                self.block = max(1, Int((Double(boardWidth) / Double(cols)).rounded(.up)))
                self.sourceOrigin = 0
                self.padLeft = 0
            }
        } else {
            self.block = 1
            self.sourceOrigin = 0
            self.padLeft = pinRight ? cols - boardWidth : (cols - boardWidth) / 2
        }
    }

    public func value(in row: [UInt8], displayCol: Int) -> UInt8 {
        if block == 1 {
            guard let index = sourceIndex(displayCol: displayCol, offset: 0) else { return 0 }
            return row[index]
        }
        var counts: [UInt8: Int] = [:]
        for offset in 0..<block {
            if let index = sourceIndex(displayCol: displayCol, offset: offset) {
                counts[row[index], default: 0] += 1
            }
        }
        // Ties favor the smaller palette index.
        return counts.max { lhs, rhs in
            lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key
        }?.key ?? 0
    }

    private func sourceIndex(displayCol: Int, offset: Int) -> Int? {
        let index: Int
        if boardWidth < displayCols {
            index = displayCol - padLeft
        } else {
            index = sourceOrigin + displayCol * block + offset
        }
        guard index >= 0 && index < boardWidth else { return nil }
        return index
    }
}
