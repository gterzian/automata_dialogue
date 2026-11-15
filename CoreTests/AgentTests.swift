import XCTest
@testable import Core

final class SystemPromptTests: XCTestCase {
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
        XCTAssertTrue(prompt.contains(
            "reason: <one full English sentence, not just the class name: the visible feature you matched, then the same class>"))
        XCTAssertTrue(prompt.contains(
            "reason_zh: <the same reason in one Simplified Chinese sentence>"))
    }

    /// The reason must be a sentence about the drawing, not the class name the
    /// model matched; the reply starts at the class line so the sentence cannot
    /// drift in front of the answer.
    func testRequiresAFullSentenceReason() {
        let prompt = SystemPrompt.build()
        XCTAssertTrue(prompt.contains(
            "Reply with exactly three lines, starting with `class:` and no other text:"))
        XCTAssertTrue(prompt.contains("one full English sentence, not just the class name"))
    }

    /// The class line comes before the reason, and the reason names the same
    /// class, so an answer that names one class on the first line and another
    /// in its sentence is invalid.
    func testRequiresTheReasonToNameTheSameClass() {
        let prompt = SystemPrompt.build()
        XCTAssertTrue(prompt.contains(
            "the class on your first line and the one in your reason must be the same word"))
    }

    /// The review window shows the reason in both languages, so the answer
    /// carries the same sentence twice, once in English and once in Chinese.
    func testRequiresAChineseCopyOfTheReason() {
        let prompt = SystemPrompt.build()
        XCTAssertTrue(prompt.contains(
            "reason_zh: <the same reason in one Simplified Chinese sentence>"))
    }

    /// The model rates the class and the engine picks the automaton, so the
    /// catalog has no place in the prompt.
    func testDoesNotNameTheCatalogOrAnAutomaton() {
        let prompt = SystemPrompt.build()
        for term in ["automaton", "automata", "### ", "id:"] {
            XCTAssertFalse(
                prompt.lowercased().contains(term),
                "prompt still mentions \(term)")
        }
        for id in Catalog.ids {
            XCTAssertFalse(prompt.contains(id), "prompt still names \(id)")
        }
    }

    func testDropsTheRetiredRatingRubric() {
        let prompt = SystemPrompt.build()
        for retired in ["rate_and_choose", "confidence", "## Method", "## Calibration anchors"] {
            XCTAssertFalse(prompt.contains(retired), "prompt still mentions \(retired)")
        }
    }

    func testPrefixStaysWithinBudget() {
        let tokens = SystemPrompt.estimatedTokenCount(of: SystemPrompt.build())
        XCTAssertLessThan(tokens, 1600, "system prompt is larger than the ~1.5k budget")
    }

    /// `complexity` is reserved for a picture that visibly mixes an ordered
    /// part with a disordered one. A coherent, recognizable figure is fully
    /// ordered, so it must land in repetition or nesting.
    func testComplexityRequiresAMixtureOfOrderAndRandomness() {
        let prompt = SystemPrompt.build()
        XCTAssertTrue(prompt.contains("- complexity: order and randomness mix in the same picture."))
        XCTAssertTrue(prompt.contains("A picture that is wholly ordered is repetition or nesting"))
        XCTAssertTrue(prompt.contains("When in doubt, choose the simpler class"))
        XCTAssertTrue(prompt.contains("Mixture test: name one ordered part and one disordered part"))
        XCTAssertTrue(prompt.contains("a wholly ordered figure is repetition or nesting, whether or not you recognize it"))
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

    /// A shape drawn again at another size is nesting, at the same size it is
    /// repetition. The prompt makes the copies' sizes the discriminator and
    /// lets nesting win that comparison.
    func testNestingWinsWhenTheCopiesDifferInSize() {
        let prompt = SystemPrompt.build()
        XCTAssertTrue(prompt.contains(
            "The copies may sit one inside another or apart"))
        XCTAssertTrue(prompt.contains(
            "a shape drawn again at a clearly different size is nesting, not repetition"))
        XCTAssertTrue(prompt.contains(
            "compare the copies' sizes first: different sizes make the class nesting, equal sizes make it repetition"))
        XCTAssertTrue(prompt.contains(
            "two or more copies of one shape at different sizes, nested or apart -> nesting"))
        XCTAssertTrue(prompt.contains(
            "Scale test: when one shape appears more than once, compare the copies."))
        XCTAssertTrue(prompt.contains(
            "Copies whose sizes differ only slightly are the same size."))
    }

    /// The signals appear in the order the model should apply them: the size
    /// comparison precedes the broad "one shape repeated" signal, which on its
    /// own would send scaled copies to repetition.
    func testChecksTheCopySizesBeforeCallingAShapeRepeated() throws {
        let prompt = SystemPrompt.build()
        let nesting = try XCTUnwrap(
            prompt.range(of: "two or more copies of one shape at different sizes"))
        let repetition = try XCTUnwrap(prompt.range(of: "one shape repeated at one size"))
        XCTAssertLessThan(nesting.lowerBound, repetition.lowerBound)
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
        XCTAssertEqual(
            body.trimmingCharacters(in: .whitespacesAndNewlines),
            SystemPrompt.build().trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

final class RatedClassParserTests: XCTestCase {
    func testParsesTheClassAndBothReasons() {
        let response = """
        class: nesting
        reason: the same triangle appears at three sizes
        reason_zh: 同一个三角形出现在三种大小上
        """
        let rating = RatedClassParser.ratedClass(from: response)
        XCTAssertEqual(rating?.behavior, .nesting)
        XCTAssertEqual(rating?.rationale, "the same triangle appears at three sizes")
        XCTAssertEqual(rating?.rationaleChinese, "同一个三角形出现在三种大小上")
    }

    /// A Chinese-speaking model may write the field with a full-width colon.
    func testParsesAChineseReasonWithAFullWidthColon() {
        let response = "class: repetition\nreason: one circle\nreason_zh：一个圆"
        XCTAssertEqual(RatedClassParser.ratedClass(from: response)?.rationaleChinese, "一个圆")
    }

    /// A missing Chinese line leaves the reason empty rather than failing the
    /// rating; the window then shows the English sentence alone.
    func testMissingChineseReasonIsEmpty() {
        let rating = RatedClassParser.ratedClass(from: "class: repetition\nreason: one circle")
        XCTAssertEqual(rating?.rationaleChinese, "")
    }

    func testParsesMarkdownEmphasis() {
        let response = "**class:** complexity\n**reason:** order and randomness"
        XCTAssertEqual(RatedClassParser.ratedClass(from: response)?.behavior, .complexity)
    }

    func testParsesBulletedFields() {
        let response = "- class: randomness\n- reason: a scatter of marks"
        let rating = RatedClassParser.ratedClass(from: response)
        XCTAssertEqual(rating?.behavior, .randomness)
        XCTAssertEqual(rating?.rationale, "a scatter of marks")
    }

    func testFallsBackToAClassNamedInProse() {
        let response = "I rate this picture nesting because one square repeats at five sizes."
        XCTAssertEqual(RatedClassParser.ratedClass(from: response)?.behavior, .nesting)
    }

    /// The explicit field is the model's commitment; a class word in the reason
    /// cannot override it.
    func testClassFieldWinsOverAClassWordInTheReason() {
        let response = "class: repetition\nreason: unlike randomness, the marks are evenly spaced"
        XCTAssertEqual(RatedClassParser.ratedClass(from: response)?.behavior, .repetition)
    }

    func testIsCaseInsensitive() {
        XCTAssertEqual(RatedClassParser.ratedClass(from: "CLASS: Nesting")?.behavior, .nesting)
    }

    func testAcceptsTrailingPunctuationOnAFieldValue() {
        XCTAssertEqual(RatedClassParser.ratedClass(from: "class: nesting.")?.behavior, .nesting)
    }

    /// The fallback matches whole words only, so a class name inside another
    /// word is not a rating.
    func testDoesNotMatchAClassInsideAWord() {
        XCTAssertNil(RatedClassParser.ratedClass(from: "antirepetition"))
    }

    func testReturnsNilWhenNoClassAppears() {
        XCTAssertNil(RatedClassParser.ratedClass(from: "I cannot decide."))
    }
}

final class SessionChoicesTests: XCTestCase {
    func testStartsEmpty() {
        XCTAssertTrue(SessionChoices().shownIDs.isEmpty)
    }

    func testPickReturnsAnEntryOfTheRatedClassAndRecordsIt() throws {
        var choices = SessionChoices()
        var generator = SeededGenerator(seed: 1)
        let picked = try XCTUnwrap(choices.pick(behavior: .nesting, using: &generator))
        XCTAssertEqual(picked.behavior, .nesting)
        XCTAssertEqual(choices.shownIDs, Set([picked.id]))
    }

    /// Every entry of a class is picked once before any of them repeats.
    func testEveryEntryIsShownOnceBeforeTheClassRepeats() throws {
        var choices = SessionChoices()
        var generator = SeededGenerator(seed: 7)
        let total = Catalog.count(of: .complexity)
        var ids: Set<String> = []
        for _ in 0..<total {
            let picked = try XCTUnwrap(choices.pick(behavior: .complexity, using: &generator))
            XCTAssertEqual(picked.behavior, .complexity)
            XCTAssertTrue(
                ids.insert(picked.id).inserted,
                "\(picked.id) repeated before the class was exhausted")
        }
        XCTAssertEqual(ids.count, total)
    }

    /// The class the picture matched outranks the no-repeat rule: once every
    /// entry of the class has been shown, that class starts over and the other
    /// classes' shown ids stay excluded.
    func testExhaustedClassStartsOverWithoutTouchingOtherClasses() throws {
        var choices = SessionChoices()
        var generator = SeededGenerator(seed: 3)
        let other = try XCTUnwrap(choices.pick(behavior: .repetition, using: &generator))
        for _ in 0..<Catalog.count(of: .complexity) {
            XCTAssertNotNil(choices.pick(behavior: .complexity, using: &generator))
        }
        XCTAssertEqual(choices.shownIDs.count, 1 + Catalog.count(of: .complexity))
        let repeated = try XCTUnwrap(choices.pick(behavior: .complexity, using: &generator))
        XCTAssertEqual(repeated.behavior, .complexity)
        XCTAssertTrue(choices.shownIDs.contains(other.id))
        XCTAssertTrue(choices.shownIDs.contains(repeated.id))
        XCTAssertEqual(choices.shownIDs.count, 2)
    }

    func testAClassMissingFromTheCatalogReturnsNil() {
        var choices = SessionChoices()
        var generator = SeededGenerator(seed: 1)
        XCTAssertNil(choices.pick(behavior: .nesting, catalog: [], using: &generator))
        XCTAssertTrue(choices.shownIDs.isEmpty)
    }
}

/// A deterministic generator, so a test can depend on `pick` drawing from it
/// rather than on the system's entropy.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
