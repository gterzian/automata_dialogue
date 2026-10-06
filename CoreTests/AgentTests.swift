import XCTest
@testable import Core

/// Thread-safe event sink for the dispatcher's `@Sendable` emit closure.
final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [AgentEvent] = []
    func append(_ event: AgentEvent) {
        lock.lock(); defer { lock.unlock() }
        events.append(event)
    }
    var all: [AgentEvent] {
        lock.lock(); defer { lock.unlock() }
        return events
    }
}

private func schemaObject(_ value: any Sendable) -> [String: any Sendable]? {
    value as? [String: any Sendable]
}

private func enumStrings(_ value: any Sendable) -> [String]? {
    value as? [String]
}

final class ToolSchemaTests: XCTestCase {
    func testChooseEnumEqualsCatalogIDs() {
        let function = schemaObject(ToolSchemas.chooseAutomaton["function"]!)
        let parameters = schemaObject(function!["parameters"]!)
        let properties = schemaObject(parameters!["properties"]!)
        let idField = schemaObject(properties!["id"]!)
        XCTAssertEqual(enumStrings(idField!["enum"]!), Catalog.ids)
    }

    func testRateEnumMatchesRatingLabels() {
        let function = schemaObject(ToolSchemas.rateInput["function"]!)
        let parameters = schemaObject(function!["parameters"]!)
        let properties = schemaObject(parameters!["properties"]!)
        let labelField = schemaObject(properties!["label"]!)
        XCTAssertEqual(enumStrings(labelField!["enum"]!), RatingLabel.allCases.map(\.rawValue))
        let confidenceField = schemaObject(properties!["confidence"]!)
        XCTAssertEqual(enumStrings(confidenceField!["enum"]!), RatingConfidence.allCases.map(\.rawValue))
    }

    func testToolNames() {
        XCTAssertEqual(ToolSchemas.all.count, 2)
        let names = ToolSchemas.all.compactMap { spec -> String? in
            guard let function = schemaObject(spec["function"]!) else { return nil }
            return function["name"] as? String
        }
        XCTAssertEqual(names, [ToolSchemas.rateInputName, ToolSchemas.chooseAutomatonName])
    }
}

final class SystemPromptTests: XCTestCase {
    func testContainsEveryCatalogID() {
        let prompt = SystemPrompt.build()
        for id in Catalog.ids {
            XCTAssertTrue(prompt.contains(id), "prompt is missing \(id)")
        }
    }

    func testContainsEverySection() {
        let prompt = SystemPrompt.build()
        for section in [
            "The four categories", "## Method", "## Output format",
            "## Calibration anchors", "## Handling specific situations",
            "Rating to inventory", "Inventory index",
        ] {
            XCTAssertTrue(prompt.contains(section), "prompt is missing \(section)")
        }
    }

    func testDropsMultiInputSummaryAndConversationalStyle() {
        let prompt = SystemPrompt.build()
        XCTAssertFalse(prompt.contains("For several inputs"))
        XCTAssertFalse(prompt.contains("continuation, a variation"))
        XCTAssertFalse(prompt.contains("When a user disagrees"))
    }

    func testPrefixStaysWithinBudget() {
        let tokens = SystemPrompt.estimatedTokenCount(of: SystemPrompt.build())
        XCTAssertLessThan(tokens, 6000, "system prompt is larger than the ~3k budget")
    }
}

final class ToolDispatcherTests: XCTestCase {
    private func makeDispatcher() -> (ToolDispatcher, EventBox) {
        let box = EventBox()
        let dispatcher = ToolDispatcher(catalog: Catalog.all) { box.append($0) }
        return (dispatcher, box)
    }

    private func ratingCall(_ label: RatingLabel = .structured) -> ToolInvocation {
        ToolInvocation(name: ToolSchemas.rateInputName, arguments: [
            "label": .string(label.rawValue),
            "confidence": .string(RatingConfidence.high.rawValue),
            "primitives": .string("bars"),
            "description": .string("five bars"),
            "reason": .string("one repeated unit"),
        ])
    }

    private func chooseCall(_ id: String = "E90") -> ToolInvocation {
        ToolInvocation(name: ToolSchemas.chooseAutomatonName, arguments: [
            "id": .string(id),
            "rationale": .string("nested"),
        ])
    }

    func testHappyPathEmitsRatingThenChoiceInOrder() async {
        let (dispatcher, box) = makeDispatcher()
        _ = await dispatcher.handle(ratingCall(.structured))
        _ = await dispatcher.handle(chooseCall("E90"))
        let events = box.all
        XCTAssertEqual(events.count, 2)
        guard case .rating(let rating) = events[0] else { return XCTFail("first event is not rating") }
        XCTAssertEqual(rating.label, .structured)
        guard case .choice(let choice) = events[1] else { return XCTFail("second event is not choice") }
        XCTAssertEqual(choice.id, "E90")
        let phase = await dispatcher.phase
        XCTAssertEqual(phase, .done)
    }

    func testChooseBeforeRateIsRejectedThenRecovers() async {
        let (dispatcher, box) = makeDispatcher()
        let first = await dispatcher.handle(chooseCall("E90"))
        XCTAssertTrue(first.contains("rate_input comes first"))
        XCTAssertTrue(box.all.isEmpty)
        // Both calls in one pass, wrong order: the next rate then choice works.
        _ = await dispatcher.handle(ratingCall(.simple))
        let second = await dispatcher.handle(chooseCall("E250"))
        XCTAssertTrue(second.contains("Displaying E250"))
        let phase = await dispatcher.phase
        XCTAssertEqual(phase, .done)
    }

    func testInvalidLabelReturnsCorrectiveAndDoesNotEmit() async {
        let (dispatcher, box) = makeDispatcher()
        let bad = ToolInvocation(name: ToolSchemas.rateInputName, arguments: [
            "label": .string("chaotic"),
            "confidence": .string("high"),
            "primitives": .string("x"),
            "description": .string("y"),
            "reason": .string("z"),
        ])
        let message = await dispatcher.handle(bad)
        XCTAssertTrue(message.contains("label must be one of"))
        XCTAssertTrue(box.all.isEmpty)
        let phase = await dispatcher.phase
        XCTAssertEqual(phase, .awaitingRating)
    }

    func testMissingRequiredFieldIsCorrective() async {
        let (dispatcher, box) = makeDispatcher()
        let bad = ToolInvocation(name: ToolSchemas.rateInputName, arguments: [
            "label": .string("simple"),
            "confidence": .string("high"),
            "primitives": .string("x"),
            "reason": .string("z"),
        ])
        let message = await dispatcher.handle(bad)
        XCTAssertTrue(message.contains("description is required"))
        XCTAssertTrue(box.all.isEmpty)
    }

    func testIDOutsideClassIsRejectedWithValidList() async {
        let (dispatcher, box) = makeDispatcher()
        _ = await dispatcher.handle(ratingCall(.simple))
        let message = await dispatcher.handle(chooseCall("E90")) // nesting
        XCTAssertTrue(message.contains("outside the classes for simple"))
        XCTAssertTrue(message.contains("E250"))
        XCTAssertTrue(box.all.count == 1) // only the rating
        let phase = await dispatcher.phase
        XCTAssertEqual(phase, .rated(.simple))
    }

    func testUnknownIDIsRejected() async {
        let (dispatcher, _) = makeDispatcher()
        _ = await dispatcher.handle(ratingCall(.random))
        let message = await dispatcher.handle(chooseCall("E999"))
        XCTAssertTrue(message.contains("is not a catalog id"))
    }

    func testLoopBoundFailsOnSixthCall() async {
        let (dispatcher, box) = makeDispatcher()
        // Five rejected choose-before-rate calls (calls 1–5), then the sixth fails.
        for _ in 0..<5 {
            _ = await dispatcher.handle(chooseCall("E90"))
        }
        let failed = await dispatcher.handle(chooseCall("E90"))
        XCTAssertTrue(failed.contains("Too many tool calls"))
        let didFail = await dispatcher.didFail
        XCTAssertTrue(didFail)
        XCTAssertTrue(box.all.contains { if case .failed = $0 { return true } else { return false } })
    }

    func testUnknownToolIsCorrective() async {
        let (dispatcher, _) = makeDispatcher()
        let message = await dispatcher.handle(ToolInvocation(name: "delete_everything"))
        XCTAssertTrue(message.contains("Unknown tool"))
    }

    func testValidIDsPerLabelFollowMapping() async {
        let (dispatcher, _) = makeDispatcher()
        let simple = await dispatcher.validIDs(for: .simple)
        XCTAssertEqual(simple.count, 9)
        XCTAssertTrue(simple.allSatisfy { Catalog.spec(id: $0)?.behavior == .repetition })
        let structured = await dispatcher.validIDs(for: .structured)
        XCTAssertEqual(structured.count, 20)
        let random = await dispatcher.validIDs(for: .random)
        XCTAssertEqual(random.count, 6)
        let complex = await dispatcher.validIDs(for: .complex)
        XCTAssertEqual(complex.count, 6)
    }
}

final class HeuristicAgentTests: XCTestCase {
    func testEmitsRatingChoiceAndFinishes() async throws {
        var events: [AgentEvent] = []
        for try await event in HeuristicAgent().run(AgentInput(text: "a structured row of bars")) {
            events.append(event)
        }
        guard case .rating(let rating) = events.first else {
            return XCTFail("expected a rating first, got \(events)")
        }
        XCTAssertEqual(rating.label, .structured)
        XCTAssertTrue(events.contains { if case .choice = $0 { return true } else { return false } })
        XCTAssertTrue(events.contains { if case .finished = $0 { return true } else { return false } })
    }

    func testChoiceIsAllowedForLabel() async throws {
        for label in RatingLabel.allCases {
            var chosen: String?
            for try await event in HeuristicAgent().run(AgentInput(text: label.rawValue)) {
                if case .choice(let choice) = event { chosen = choice.id }
            }
            let spec = try XCTUnwrap(Catalog.spec(id: chosen ?? ""))
            XCTAssertTrue(label.allowedBehaviors.contains(spec.behavior), "\(label) chose \(spec.id)")
        }
    }

    func testIsDeterministic() async throws {
        func run() async throws -> [String] {
            var ids: [String] = []
            for try await event in HeuristicAgent().run(AgentInput(text: "same input", imageURL: URL(fileURLWithPath: "/tmp/x.png"))) {
                if case .choice(let choice) = event { ids.append(choice.id) }
            }
            return ids
        }
        let a = try await run()
        let b = try await run()
        XCTAssertEqual(a, b)
    }
}
