import XCTest
@testable import Core

final class TranscriptStoreTests: XCTestCase {
    private func rating(_ label: RatingLabel = .structured) -> Rating {
        Rating(label: label, confidence: .high, primitives: "bars", description: "five bars", reason: "repetition")
    }

    func testApplyRatingAndChoiceAppendsInOrder() {
        let store = TranscriptStore()
        _ = store.apply(.rating(rating(.random)))
        _ = store.apply(.choice(Choice(id: "E30", rationale: "tangle")))
        XCTAssertEqual(store.count, 2)
        guard case .rating(let r) = store.entry(at: 0)?.kind else { return XCTFail("expected rating") }
        XCTAssertEqual(r.label, .random)
        guard case .choice(let c) = store.entry(at: 1)?.kind else { return XCTFail("expected choice") }
        XCTAssertEqual(c.id, "E30")
    }

    func testStreamingTextAccumulatesInOneRowThenSettles() {
        let store = TranscriptStore()
        _ = store.apply(.text("structured: "))
        _ = store.apply(.text("displaying E90."))
        XCTAssertEqual(store.count, 1)
        guard case .assistantMessage(let text, true) = store.entry(at: 0)?.kind else {
            return XCTFail("expected streaming assistant row")
        }
        XCTAssertEqual(text, "structured: displaying E90.")
        _ = store.apply(.finished)
        guard case .assistantMessage(let final, false) = store.entry(at: 0)?.kind else {
            return XCTFail("expected settled row")
        }
        XCTAssertEqual(final, "structured: displaying E90.")
        XCTAssertEqual(store.count, 1)
    }

    func testFailureSettlesThenAddsError() {
        let store = TranscriptStore()
        _ = store.apply(.text("partial"))
        _ = store.apply(.failed("boom"))
        XCTAssertEqual(store.count, 2)
        guard case .assistantMessage(_, false) = store.entry(at: 0)?.kind else {
            return XCTFail("streaming row should settle")
        }
        guard case .errorMessage(let message) = store.entry(at: 1)?.kind else {
            return XCTFail("expected error row")
        }
        XCTAssertEqual(message, "boom")
    }

    func testAppendUserInputAndSearch() {
        let store = TranscriptStore()
        store.append(.userInput(text: "a tangled polyline", imagePath: "/tmp/x.png"))
        store.append(.rating(rating(.random)))
        XCTAssertEqual(store.search("polyline"), [0])
        XCTAssertEqual(store.search("rand"), [1])
        XCTAssertTrue(store.search("missing").isEmpty)
    }

    func testPersistenceRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RaterTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("transcript.jsonl")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = TranscriptStore(transcriptURL: url)
        store.append(.userInput(text: "hello", imagePath: nil))
        _ = store.apply(.rating(rating(.simple)))
        _ = store.apply(.text("done"))
        _ = store.apply(.finished)

        let loaded = TranscriptStore.load(from: url)
        XCTAssertEqual(loaded.count, 3)
        guard case .userInput(let text, _) = loaded[0].kind else { return XCTFail("expected input") }
        XCTAssertEqual(text, "hello")
        guard case .assistantMessage(let final, false) = loaded[2].kind else {
            return XCTFail("expected settled assistant row persisted once")
        }
        XCTAssertEqual(final, "done")
    }
}

final class StreamingRefreshGateTests: XCTestCase {
    func testNewRowRefreshesImmediately() {
        var gate = StreamingRefreshGate(batchInterval: 0.25)
        XCTAssertTrue(gate.shouldRefresh(entryID: "a", text: "x", isStreaming: true, now: 0))
    }

    func testBatchesLiveChunks() {
        var gate = StreamingRefreshGate(batchInterval: 0.25)
        XCTAssertTrue(gate.shouldRefresh(entryID: "a", text: "x", isStreaming: true, now: 0))
        XCTAssertFalse(gate.shouldRefresh(entryID: "a", text: "xy", isStreaming: true, now: 0.1))
        XCTAssertTrue(gate.shouldRefresh(entryID: "a", text: "xyz", isStreaming: true, now: 0.3))
    }

    func testSettleRefreshesImmediately() {
        var gate = StreamingRefreshGate(batchInterval: 0.25)
        XCTAssertTrue(gate.shouldRefresh(entryID: "a", text: "x", isStreaming: true, now: 0))
        XCTAssertTrue(gate.shouldRefresh(entryID: "a", text: "x", isStreaming: false, now: 0.01))
    }

    func testNoRefreshWhenUnchanged() {
        var gate = StreamingRefreshGate(batchInterval: 0.25)
        XCTAssertTrue(gate.shouldRefresh(entryID: "a", text: "x", isStreaming: true, now: 0))
        XCTAssertFalse(gate.shouldRefresh(entryID: "a", text: "x", isStreaming: true, now: 1.0))
    }
}

final class HeightCacheTests: XCTestCase {
    func testMeasuresOncePerWidth() {
        let cache = HeightCache()
        var calls = 0
        let measure = { () -> CGFloat in calls += 1; return 42 }
        XCTAssertEqual(cache.height(for: "a", width: 100, measure: measure), 42)
        XCTAssertEqual(cache.height(for: "a", width: 100, measure: measure), 42)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(cache.height(for: "a", width: 200, measure: measure), 42)
        XCTAssertEqual(calls, 2)
    }

    func testTagMismatchRemeasures() {
        let cache = HeightCache()
        cache.store("a", width: 100, height: 10, tag: "v1")
        XCTAssertEqual(cache.cached(for: "a", width: 100)?.tag, "v1")
        XCTAssertNil(cache.cached(for: "a", width: 150))
        cache.invalidate("a")
        XCTAssertNil(cache.cached(for: "a", width: 100))
    }

    func testNilTagDoesNotHitTaggedEntry() {
        let cache = HeightCache()
        cache.store("a", width: 100, height: 10, tag: "v1")
        var measured = false
        _ = cache.height(for: "a", width: 100, tag: nil) { measured = true; return 99 }
        XCTAssertTrue(measured)
    }
}
