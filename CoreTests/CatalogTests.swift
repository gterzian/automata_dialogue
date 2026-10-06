import XCTest
@testable import Core

final class CatalogTests: XCTestCase {
    func testHasExactly32UniqueEntries() {
        XCTAssertEqual(Catalog.all.count, 32)
        XCTAssertEqual(Set(Catalog.ids).count, 32)
    }

    func testBehaviorCounts() {
        XCTAssertEqual(Catalog.count(of: .repetition), 9)
        XCTAssertEqual(Catalog.count(of: .nesting), 11)
        XCTAssertEqual(Catalog.count(of: .randomness), 6)
        XCTAssertEqual(Catalog.count(of: .complexity), 6)
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
        XCTAssertEqual(Catalog.spec(id: "T1599")?.display.stepLimit, 8300)
    }

    func testColumnWidthForWideBoards() {
        XCTAssertEqual(Catalog.spec(id: "T1635")?.board.width, 6101)
        XCTAssertEqual(Catalog.spec(id: "T2049")?.board.width, 6101)
    }
}
