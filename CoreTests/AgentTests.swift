import XCTest
@testable import Core

final class SystemPromptTests: XCTestCase {
    func testEmbedsEveryCatalogID() {
        let prompt = SystemPrompt.build()
        for id in Catalog.ids {
            XCTAssertTrue(prompt.contains(id), "prompt is missing \(id)")
        }
    }

    func testEachEntryCarriesItsClass() {
        let prompt = SystemPrompt.build()
        for spec in Catalog.all {
            XCTAssertTrue(
                prompt.contains("\(spec.id) | \(spec.behavior.rawValue)"),
                "prompt is missing the class line for \(spec.id)"
            )
        }
    }

    /// The `look` sentence stays out of the submitted prompt: it is the bulk of
    /// the catalog and the class, not the look, is what the model must match.
    func testPromptOmitsTheLookSentences() {
        let prompt = SystemPrompt.build()
        for spec in Catalog.all where !spec.look.isEmpty {
            XCTAssertFalse(prompt.contains(spec.look), "prompt still carries the look for \(spec.id)")
        }
    }

    func testDescribesTheFourClasses() {
        let prompt = SystemPrompt.build()
        for behavior in Behavior.allCases {
            XCTAssertTrue(
                prompt.contains("- \(behavior.rawValue):"),
                "prompt is missing the \(behavior.rawValue) description"
            )
        }
    }

    func testStatesTheAnswerFormat() {
        let prompt = SystemPrompt.build()
        XCTAssertTrue(prompt.contains("class: <one of repetition, nesting, randomness, complexity>"))
        XCTAssertTrue(prompt.contains("id: <one id from the list whose class is the class on the first line>"))
        XCTAssertTrue(prompt.contains(
            "reason: <one full sentence, not just the class name: the visible feature you matched, then the class it puts the drawing in>"))
    }

    /// The reason must be a sentence about the drawing, not the class name the
    /// model matched; the reply starts at the class line so the sentence cannot
    /// drift in front of the answer.
    func testRequiresAFullSentenceReason() {
        let prompt = SystemPrompt.build()
        XCTAssertTrue(prompt.contains(
            "Reply with exactly three lines, starting with `class:` and no other text:"))
        XCTAssertTrue(prompt.contains("one full sentence, not just the class name"))
    }

    /// The reason and the chosen id must agree: the observed failure named
    /// randomness in the reason and then replied with a complexity id.
    func testRequiresTheIDToCarryTheClassTheReasonNames() {
        let prompt = SystemPrompt.build()
        XCTAssertTrue(prompt.contains(
            "The class printed next to your id must be the class you decided; the answer is wrong when those differ."))
        XCTAssertTrue(prompt.contains(
            "the class after your id must be the same word as the class your reason names"))
    }

    func testSaysToMatchByBehaviorNotLikeness() {
        let prompt = SystemPrompt.build()
        XCTAssertTrue(prompt.contains("Do not look for an automaton that resembles the image."))
        XCTAssertTrue(prompt.contains("the match is conceptual, not visual"))
    }

    func testDropsTheRetiredRatingRubric() {
        let prompt = SystemPrompt.build()
        for retired in ["rate_and_choose", "confidence", "## Method", "## Calibration anchors"] {
            XCTAssertFalse(prompt.contains(retired), "prompt still mentions \(retired)")
        }
    }

    func testPrefixStaysWithinBudget() {
        let tokens = SystemPrompt.estimatedTokenCount(of: SystemPrompt.build())
        XCTAssertLessThan(tokens, 2500, "system prompt is larger than the ~1k budget")
    }

    /// `complexity` is reserved for a picture that visibly mixes an ordered
    /// part with a disordered one. A coherent, recognizable figure is fully
    /// ordered, so it must land in repetition or nesting; the old rubric's
    /// "designed or meaningful" test sent the house to complexity.
    func testComplexityRequiresAMixtureOfOrderAndRandomness() {
        let prompt = SystemPrompt.build()
        XCTAssertTrue(prompt.contains("- complexity: order and randomness mix in the same picture."))
        XCTAssertTrue(prompt.contains("A picture that is wholly ordered is repetition or nesting"))
        XCTAssertTrue(prompt.contains("When in doubt, choose the simpler class"))
        XCTAssertTrue(prompt.contains("Mixture test: name one ordered part and one disordered part"))
        XCTAssertTrue(prompt.contains("a wholly ordered figure is repetition (or nesting), whether or not you recognize it"))
    }

    func testDoesNotTreatARecognizableSubjectAsComplexity() {
        let prompt = SystemPrompt.build()
        for retired in [
            "reads as designed or meaningful",
            "character or glyph of several interacting strokes -> complexity",
            "Sensitivity: imagine deleting one stroke",
            "unless the organizing idea is clear",
        ] {
            XCTAssertFalse(prompt.contains(retired), "prompt still uses the retired subject test: \(retired)")
        }
    }

    /// The artifact is the human-readable copy of the prompt; nothing generates
    /// one from the other, so this fails when they drift (see `AGENTS.md`).
    func testArtifactMatchesTheBuiltPrompt() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // CoreTests
            .deletingLastPathComponent()   // repository root
        let artifact = repoRoot
            .appendingPathComponent("artifacts")
            .appendingPathComponent("System prompt_ choosing an automaton.md")
        let markdown = try String(contentsOf: artifact, encoding: .utf8)
        guard let separator = markdown.range(of: "\n---\n") else {
            return XCTFail("artifact has no prompt body separator")
        }
        let body = markdown[separator.upperBound...]
            .replacingOccurrences(
                of: "<!-- AUTOMATA -->",
                with: Catalog.promptIndexLines.joined(separator: "\n")
            )
        XCTAssertEqual(
            body.trimmingCharacters(in: .whitespacesAndNewlines),
            SystemPrompt.build().trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

final class ChoiceParserTests: XCTestCase {
    func testParsesIDAndReasonFields() {
        let response = "id: E90\nreason: nested Sierpinski holes match the drawing"
        let choice = ChoiceParser.choice(from: response)
        XCTAssertEqual(choice?.id, "E90")
        XCTAssertEqual(choice?.rationale, "nested Sierpinski holes match the drawing")
    }

    func testParsesMarkdownEmphasis() {
        let response = "**id:** E110\n**reason:** one-sided growth"
        XCTAssertEqual(ChoiceParser.choice(from: response)?.id, "E110")
    }

    func testParsesBulletedFields() {
        let response = "- id: E90\n- reason: nested holes"
        let choice = ChoiceParser.choice(from: response)
        XCTAssertEqual(choice?.id, "E90")
        XCTAssertEqual(choice?.rationale, "nested holes")
    }

    func testFallsBackToAnIDInProse() {
        let response = "I would display E54 because it has moving structures."
        XCTAssertEqual(ChoiceParser.choice(from: response)?.id, "E54")
    }

    func testPrefersTheLongestIDMatch() {
        let response = "The entry E90.sparse matches the sparse speckle."
        XCTAssertEqual(ChoiceParser.choice(from: response)?.id, "E90.sparse")
    }

    func testMatchesAnIDWithTrailingPunctuation() {
        XCTAssertEqual(ChoiceParser.choice(from: "id: E90.\nreason: holes")?.id, "E90")
        XCTAssertEqual(ChoiceParser.choice(from: "The Sierpinski entry is E90.")?.id, "E90")
    }

    func testDoesNotMatchAnIDInsideAWord() {
        XCTAssertNil(ChoiceParser.choice(from: "prefixE90suffix"))
    }

    func testReturnsNilWhenNoCatalogIDAppears() {
        XCTAssertNil(ChoiceParser.choice(from: "I cannot decide."))
    }

    func testIgnoresAnUnknownID() {
        XCTAssertNil(ChoiceParser.choice(from: "id: E999\nreason: none"))
    }

    func testIDFieldWinsOverAnIDInTheReason() {
        let response = "id: T237\nreason: unlike E110, the holes are large"
        XCTAssertEqual(ChoiceParser.choice(from: response)?.id, "T237")
    }

    func testIsCaseInsensitive() {
        XCTAssertEqual(ChoiceParser.choice(from: "ID: e250")?.id, "E250")
        XCTAssertEqual(ChoiceParser.choice(from: "id: e110")?.id, "E110")
    }

    /// A bare class name or a fragment is not a reason. The engine uses this to
    /// ask once more for the full sentence the prompt requires.
    func testReasonCompletenessRejectsLabels() {
        XCTAssertFalse(Choice(id: "E30", rationale: "randomness").hasFullReason)
        XCTAssertFalse(Choice(id: "E30", rationale: "Randomness.").hasFullReason)
        XCTAssertFalse(Choice(id: "E30", rationale: "repetition because stripes").hasFullReason)
        XCTAssertFalse(Choice(id: "E30", rationale: "").hasFullReason)
        XCTAssertTrue(Choice(
            id: "E30",
            rationale: "The marks scatter with no regular part, so the class is randomness."
        ).hasFullReason)
    }
}

final class ChoiceHistoryTests: XCTestCase {
    func testIsEmptyUntilAChoiceIsRecorded() {
        XCTAssertTrue(ChoiceHistory().excludedIDs.isEmpty)
        XCTAssertEqual(ChoiceHistory().userTurn(""), "")
        XCTAssertEqual(ChoiceHistory().userTurn("look"), "look")
    }

    func testKeepsOnlyTheMostRecentChoices() {
        var history = ChoiceHistory()
        for index in 0..<(ChoiceHistory.limit + 5) { history.record("id\(index)") }
        XCTAssertEqual(history.excludedIDs.count, ChoiceHistory.limit)
        XCTAssertEqual(history.excludedIDs.first, "id5")
        XCTAssertEqual(history.excludedIDs.last, "id\(ChoiceHistory.limit + 4)")
    }

    func testUserTurnAppendsTheExclusionNote() {
        var history = ChoiceHistory()
        history.record("E90")
        history.record("E110")
        let turn = history.userTurn("")
        XCTAssertTrue(turn.contains("Do not choose these ids"))
        XCTAssertTrue(turn.contains("E90, E110"))
        XCTAssertTrue(turn.contains("Choose a different automaton of the same class."))
    }

    func testUserTurnKeepsTheSubmittedTextFirst() {
        var history = ChoiceHistory()
        history.record("E90")
        XCTAssertTrue(history.userTurn("look").hasPrefix("look\n\n"))
    }
}
