import Foundation

/// Owns the full, ordered transcript off-main. Settled entries are persisted as
/// append-only JSONL; the streaming assistant row is mutated in memory and
/// persisted once when the run finishes or fails (design doc §7).
public final class TranscriptStore: @unchecked Sendable {
    /// What an `apply(_:)` call changed, so a view can refresh minimally.
    public enum Mutation: Equatable, Sendable {
        case appended(id: String)
        case updated(id: String)
        case unchanged
    }

    private let lock = NSLock()
    private var storage: [TranscriptEntry] = []
    private var streamingID: String?
    private let transcriptURL: URL?

    public init(transcriptURL: URL? = nil) {
        self.transcriptURL = transcriptURL
    }

    // MARK: - Reading

    public var count: Int {
        lock.withLock { storage.count }
    }

    public var entries: [TranscriptEntry] {
        lock.withLock { storage }
    }

    public func entry(at index: Int) -> TranscriptEntry? {
        lock.withLock { index >= 0 && index < storage.count ? storage[index] : nil }
    }

    public func clear() {
        lock.withLock {
            storage.removeAll()
            streamingID = nil
        }
    }

    /// Case-insensitive substring search over each row's searchable text.
    public func search(_ query: String) -> [Int] {
        guard !query.isEmpty else { return [] }
        let needle = query.lowercased()
        return lock.withLock {
            storage.enumerated()
                .filter { $0.element.searchableText.lowercased().contains(needle) }
                .map(\.offset)
        }
    }

    // MARK: - Writing

    @discardableResult
    public func append(_ kind: TranscriptEntryKind, id: String = UUID().uuidString) -> TranscriptEntry {
        let entry = TranscriptEntry(id: id, kind: kind)
        lock.withLock {
            storage.append(entry)
        }
        persist(entry)
        return entry
    }

    /// Applies one agent event. `.text` chunks extend a single streaming
    /// assistant row; `.finished` settles it.
    @discardableResult
    public func apply(_ event: AgentEvent) -> Mutation {
        switch event {
        case .choice(let choice):
            let entry = TranscriptEntry(id: UUID().uuidString, kind: .choice(choice))
            lock.withLock { storage.append(entry) }
            persist(entry)
            return .appended(id: entry.id)
        case .text(let chunk):
            return lock.withLock {
                if let streamingID,
                   let index = storage.firstIndex(where: { $0.id == streamingID }),
                   case .assistantMessage(let text, true) = storage[index].kind {
                    storage[index].kind = .assistantMessage(text: text + chunk, isStreaming: true)
                    return .updated(id: streamingID)
                }
                let entry = TranscriptEntry(
                    id: UUID().uuidString,
                    kind: .assistantMessage(text: chunk, isStreaming: true)
                )
                storage.append(entry)
                streamingID = entry.id
                return .appended(id: entry.id)
            }
        case .finished:
            return lock.withLock {
                guard let streamingID,
                      let index = storage.firstIndex(where: { $0.id == streamingID }),
                      case .assistantMessage(let text, _) = storage[index].kind else {
                    return .unchanged
                }
                storage[index].kind = .assistantMessage(text: text, isStreaming: false)
                self.streamingID = nil
                persist(storage[index])
                return .updated(id: streamingID)
            }
        case .failed(let message):
            return lock.withLock {
                if let streamingID,
                   let index = storage.firstIndex(where: { $0.id == streamingID }),
                   case .assistantMessage(let text, _) = storage[index].kind {
                    storage[index].kind = .assistantMessage(text: text, isStreaming: false)
                    self.streamingID = nil
                    persist(storage[index])
                }
                let entry = TranscriptEntry(id: UUID().uuidString, kind: .errorMessage(message))
                storage.append(entry)
                persist(entry)
                return .appended(id: entry.id)
            }
        }
    }

    /// Replaces the in-memory transcript (used when reloading a persisted one).
    public func rebuild(from entries: [TranscriptEntry]) {
        lock.withLock {
            storage = entries
            streamingID = nil
        }
    }

    // MARK: - Persistence

    private func persist(_ entry: TranscriptEntry) {
        guard let transcriptURL else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(entry) else { return }
        try? FileManager.default.createDirectory(
            at: transcriptURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: transcriptURL.path) {
            FileManager.default.createFile(atPath: transcriptURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: transcriptURL) else { return }
        defer { try? handle.close() }
        // Append: a failed seek means we cannot trust the offset, so skip the
        // entry rather than overwrite earlier lines from offset zero.
        guard (try? handle.seekToEnd()) != nil else { return }
        try? handle.write(contentsOf: data)
        try? handle.write(contentsOf: Data("\n".utf8))
    }

    /// Loads a transcript previously written by `persist`.
    public static func load(from url: URL) -> [TranscriptEntry] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                guard let lineData = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(TranscriptEntry.self, from: lineData)
            }
    }
}
