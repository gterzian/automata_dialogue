import XCTest
@testable import Core

final class CatalogTests: XCTestCase {
    func testHasExactly45UniqueEntries() {
        XCTAssertEqual(Catalog.all.count, 45)
        XCTAssertEqual(Set(Catalog.ids).count, 45)
    }

    func testBehaviorCounts() {
        XCTAssertEqual(Catalog.count(of: .repetition), 12)
        XCTAssertEqual(Catalog.count(of: .nesting), 14)
        XCTAssertEqual(Catalog.count(of: .randomness), 10)
        XCTAssertEqual(Catalog.count(of: .complexity), 9)
    }

    func testEverySpecHasALookLine() {
        for spec in Catalog.all {
            XCTAssertFalse(spec.look.isEmpty, "\(spec.id) has no look line")
            XCTAssertFalse(spec.look.contains("\n"), "\(spec.id) look spans lines")
        }
    }

    func testStartConditionsMatchInventory() {
        XCTAssertEqual(Catalog.spec(id: "E110")?.board.start, .rightmost)
        XCTAssertEqual(Catalog.spec(id: "E54")?.board.start, .random(seed: 54))
        XCTAssertEqual(Catalog.spec(id: "E30.block1100")?.board.start, .block([1, 1, 0, 0]))
        XCTAssertEqual(Catalog.spec(id: "K2R2-20.seed195")?.board.start, .seed(number: 195, colors: 2))
        XCTAssertEqual(Catalog.spec(id: "T1329.seed916")?.board.start, .seed(number: 916, colors: 3))
        XCTAssertEqual(Catalog.spec(id: "T1329.seed54889")?.board.start, .seed(number: 54_889, colors: 3))
        XCTAssertEqual(Catalog.spec(id: "E22.seed19")?.board.start, .seed(number: 19, colors: 2))
        XCTAssertEqual(Catalog.spec(id: "E90.sparse")?.board.start, .random(seed: 905, density: 0.05))
        XCTAssertEqual(Catalog.spec(id: "E126.pairs")?.board.start, .randomBlocks(seed: 126))
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
}
