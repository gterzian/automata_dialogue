import XCTest
@testable import Core

final class CatalogTests: XCTestCase {
    func testHasExpectedUniqueEntries() {
        XCTAssertEqual(Catalog.all.count, 111)
        XCTAssertEqual(Set(Catalog.ids).count, 111)
    }

    func testBehaviorCounts() {
        XCTAssertEqual(Catalog.count(of: .repetition), 29)
        XCTAssertEqual(Catalog.count(of: .nesting), 28)
        XCTAssertEqual(Catalog.count(of: .randomness), 40)
        XCTAssertEqual(Catalog.count(of: .complexity), 14)
    }

    /// E62's single-cell triangle looks busy but is a period-3 weave, so it is
    /// repetition, not complexity (see `artifacts/`).
    func testE62IsRepetition() {
        XCTAssertEqual(Catalog.spec(id: "E62")?.behavior, .repetition)
    }

    /// Rule 106's random-row picture is a field of diagonal static, not the
    /// localized interacting structures complexity requires; its single-cell
    /// start is a single straight diagonal line (see `artifacts/`).
    func testE106RandIsRandomness() {
        XCTAssertEqual(Catalog.spec(id: "E106.rand")?.behavior, .randomness)
    }

    /// Rules that settle quickly (short whole-row period, or near-zero damage)
    /// are not complexity, however busy the transient looks. `E154.rand` comes
    /// from a non-spreading rule whose random row forms a fixed diagonal
    /// texture; `T1662` repeats every 8 steps; `T219.rand` freezes into a fixed
    /// field of straight lines (NKS ch. 6 calls rule 219 class 2 or 4, not 3);
    /// `T2046.rand` freezes; `K2R2-52.rand` repeats every 1 to 3 steps (all
    /// verified over several seeds with `tools/catalog-audit`).
    func testSettlingRandomRowsAreNotComplexity() {
        XCTAssertEqual(Catalog.spec(id: "E154.rand")?.behavior, .randomness)
        XCTAssertEqual(Catalog.spec(id: "T1662")?.behavior, .repetition)
        XCTAssertEqual(Catalog.spec(id: "T219.rand")?.behavior, .repetition)
        XCTAssertEqual(Catalog.spec(id: "T2046.rand")?.behavior, .randomness)
        XCTAssertEqual(Catalog.spec(id: "K2R2-52.rand")?.behavior, .randomness)
    }

    /// Entries that drift sideways declare a follow rate; a centred or
    /// symmetric entry stays fixed.
    func testFollowRates() {
        XCTAssertEqual(Catalog.spec(id: "E28")?.display.follow, Follow.right)
        XCTAssertEqual(Catalog.spec(id: "E60")?.display.follow, Follow.right)
        XCTAssertEqual(Catalog.spec(id: "E90")?.display.follow, Follow.none)
    }

    /// Injected randomness is deterministic, so `makeProgram()` stays the
    /// golden entry point.
    func testInjectedRandomnessIsDeterministic() {
        guard let spec = Catalog.spec(id: "E90.inject") else { return XCTFail("missing E90.inject") }
        XCTAssertNotNil(spec.board.injection)
        var a = spec.makeProgram()
        var b = spec.makeProgram()
        for _ in 0..<32 {
            a.step()
            b.step()
        }
        XCTAssertEqual(RowHash.fnv1a(a.row()), RowHash.fnv1a(b.row()))
    }

    func testEverySpecHasALookLine() {
        for spec in Catalog.all {
            XCTAssertFalse(spec.look.isEmpty, "\(spec.id) has no look line")
            XCTAssertFalse(spec.look.contains("\n"), "\(spec.id) look spans lines")
        }
    }

    func testStartConditionsMatchInventory() {
        XCTAssertEqual(Catalog.spec(id: "E110")?.board.start, .rightmost)
        XCTAssertEqual(Catalog.spec(id: "E54")?.board.start, .center)
        XCTAssertEqual(Catalog.spec(id: "E54.rand")?.board.start, .random(seed: 54))
        XCTAssertEqual(Catalog.spec(id: "E30.block1100")?.board.start, .block([1, 1, 0, 0]))
        XCTAssertEqual(Catalog.spec(id: "K2R2-20.seed195")?.board.start, .seed(number: 195, colors: 2))
        XCTAssertEqual(Catalog.spec(id: "T1329.seed916")?.board.start, .seed(number: 916, colors: 3))
        XCTAssertEqual(Catalog.spec(id: "T1329.seed54889")?.board.start, .seed(number: 54_889, colors: 3))
        XCTAssertEqual(Catalog.spec(id: "T357.seed28")?.board.start, .seed(number: 28, colors: 3))
        XCTAssertEqual(Catalog.spec(id: "E22.seed19")?.board.start, .seed(number: 19, colors: 2))
        XCTAssertEqual(Catalog.spec(id: "E90.sparse")?.board.start, .random(seed: 905, density: 0.05))
        XCTAssertEqual(Catalog.spec(id: "E126.pairs")?.board.start, .randomBlocks(seed: 126))
        XCTAssertEqual(Catalog.spec(id: "T1587.rand")?.board.start, .random(seed: 1587))
        XCTAssertEqual(Catalog.spec(id: "T237.rand")?.board.start, .random(seed: 237))
        XCTAssertEqual(Catalog.spec(id: "K2R2-52.rand")?.board.start, .random(seed: 52))
        XCTAssertEqual(Catalog.spec(id: "T1599")?.display.stepLimit, 8300)
        XCTAssertEqual(Catalog.spec(id: "E110.rand")?.display.stepLimit, 700)
    }

    func testColumnWidthForWideBoards() {
        XCTAssertEqual(Catalog.spec(id: "T1635")?.board.width, 6101)
        XCTAssertEqual(Catalog.spec(id: "T2049")?.board.width, 6101)
    }

    /// The next-nearest-neighbor entries are the only radius-2 program.
    func testK2R2ProgramStateCount() {
        guard let spec = Catalog.spec(id: "K2R2-20.seed195") else { return XCTFail("missing entry") }
        XCTAssertEqual(spec.stateCount, 2)
        XCTAssertEqual(spec.gpu, .k2r2(code: 20))
    }

    /// A run reseeds `.rand` entries so re-showing one gives a different
    /// picture, while `makeProgram()` stays the deterministic entry point for
    /// the goldens (inventory §1.4).
    func testRandomStartsReseedPerRun() {
        guard let rand = Catalog.spec(id: "E90.rand"),
              case .random(let seed, let density) = rand.board.start else {
            return XCTFail("missing E90.rand random start")
        }
        let fresh = rand.withRandomSeed(seed &+ 1)
        XCTAssertEqual(
            fresh.board,
            Board(width: rand.board.width, height: rand.board.height,
                  start: .random(seed: seed &+ 1, density: density))
        )
        XCTAssertNotEqual(
            RowHash.fnv1a(fresh.makeProgram().row()),
            RowHash.fnv1a(rand.makeProgram().row())
        )
        // Re-applying the stored seed reproduces the deterministic entry.
        XCTAssertEqual(
            RowHash.fnv1a(rand.withRandomSeed(seed).makeProgram().row()),
            RowHash.fnv1a(rand.makeProgram().row())
        )
    }

    func testWithRandomSeedLeavesNonRandomStartsAlone() {
        guard let deterministic = Catalog.spec(id: "E90") else { return XCTFail("missing E90") }
        XCTAssertEqual(deterministic.withRandomSeed(7).board, deterministic.board)
        XCTAssertEqual(
            RowHash.fnv1a(deterministic.withRandomSeed(7).makeProgram().row()),
            RowHash.fnv1a(deterministic.makeProgram().row())
        )
        // `.pairs` is a fixed 2-cell block draw, not a `.rand` row.
        guard let pairs = Catalog.spec(id: "E126.pairs") else { return XCTFail("missing E126.pairs") }
        XCTAssertEqual(pairs.withRandomSeed(7).board, pairs.board)
    }
}
