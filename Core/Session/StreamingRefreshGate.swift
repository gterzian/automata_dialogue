import Foundation

/// Batched-refresh decision for the streaming assistant row, extracted from the
/// view coordinator so it is unit-testable. Delta rates can be high; the gate
/// allows a refresh only:
///  - immediately when a new streaming row starts, or
///  - when the content changed and `batchInterval` has elapsed, or
///  - when the row settles (the flag flip must render even if the text did not).
public struct StreamingRefreshGate: Sendable {
    public let batchInterval: TimeInterval

    public private(set) var lastStreamedID: String?
    public private(set) var lastStreamedContent: String?
    public private(set) var lastStreamedWasStreaming = false
    public private(set) var lastStreamedAt: TimeInterval = 0

    public init(batchInterval: TimeInterval = 0.25) {
        self.batchInterval = batchInterval
    }

    public mutating func shouldRefresh(
        entryID: String,
        text: String,
        isStreaming: Bool,
        now: TimeInterval
    ) -> Bool {
        var shouldRefresh = false
        if lastStreamedID != entryID {
            lastStreamedID = entryID
            shouldRefresh = true
        } else if lastStreamedContent != text || lastStreamedWasStreaming != isStreaming {
            shouldRefresh = !isStreaming || now - lastStreamedAt >= batchInterval
        }
        if shouldRefresh {
            lastStreamedAt = now
            lastStreamedContent = text
            lastStreamedWasStreaming = isStreaming
        }
        return shouldRefresh
    }
}
