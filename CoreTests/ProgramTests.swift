import XCTest
@testable import Core

final class ProgramTests: XCTestCase {
    /// Rule 90 from a single center cell has the Sierpinski property:
    /// row 1 = {1,0,1} centered on the seed.
    func testElementaryRule90SeedRow() {
        var program = ElementaryCA(rule: 90, width: 7, start: .centerCell)
        XCTAssertEqual(program.row(), [0, 0, 0, 1, 0, 0, 0])
        program.step()
        XCTAssertEqual(program.row(), [0, 0, 1, 0, 1, 0, 0])
        program.step()
        XCTAssertEqual(program.row(), [0, 1, 0, 0, 0, 1, 0])
    }

    /// Every elementary rule's closed Boolean form must agree with its rule
    /// table for all eight neighborhoods (inventory §1.1).
    func testClosedFormsMatchRuleTables() {
        let closedForms: [UInt8: (_ l: UInt8, _ c: UInt8, _ r: UInt8) -> UInt8] = [
            250: { l, _, r in l | r },
            90: { l, _, r in l ^ r },
            60: { l, c, _ in l ^ c },
            150: { l, c, r in l ^ c ^ r },
            105: { l, c, r in 1 ^ l ^ c ^ r },
            129: { l, c, r in (l == c && c == r) ? 1 : 0 },
            30: { l, c, r in l ^ (c | r) },
            225: { l, c, r in 1 ^ l ^ (c | r) },
            110: { l, c, r in (c | r) & ~(l & c & r) & 1 },
            54: { l, c, r in c ^ (l | r) },
        ]
        for (rule, form) in closedForms {
            for n in 0..<8 {
                let l = UInt8((n >> 2) & 1)
                let c = UInt8((n >> 1) & 1)
                let r = UInt8(n & 1)
                let fromTable = (rule >> UInt8(n)) & 1
                XCTAssertEqual(fromTable, form(l, c, r), "rule \(rule) neighborhood \(n)")
            }
        }
    }

    /// Inventory §1.2: code 777 in base 3 is `1001210`, i.e. sum 0 → 0,
    /// 1 → 1, 2 → 2, 3 → 1, 4 → 0, 5 → 0, 6 → 1. A single gray cell therefore
    /// yields three gray cells on the first step.
    func testTotalisticTableExtraction() {
        var program = TotalisticCA(code: 777, colors: 3, width: 7)
        XCTAssertEqual(program.row(), [0, 0, 0, 1, 0, 0, 0])
        program.step()
        XCTAssertEqual(program.row(), [0, 0, 1, 1, 1, 0, 0])
    }

    /// Codes divisible by 3 keep an empty background empty (inventory §1.2).
    func testTotalisticBackgroundStaysEmpty() {
        var program = TotalisticCA(code: 1329, colors: 3, width: 9)
        XCTAssertEqual(program.row().filter { $0 == 0 }.count, 8)
        program.step()
        XCTAssertEqual(program.row().first, 0)
        XCTAssertEqual(program.row().last, 0)
    }

    /// Inventory §1.3: code 20 is `010100`, so sums 2 and 4 give black and
    /// all other sums give white. Two adjacent black cells set both neighbors'
    /// and each other's five-cell sum to 2, giving a run four cells wide.
    func testK2R2TableExtraction() {
        let row: [UInt8] = [0, 0, 0, 1, 1, 0, 0, 0, 0]
        var program = K2R2CA(code: 20, width: row.count, row: row)
        program.step()
        XCTAssertEqual(program.row(), [0, 0, 1, 1, 1, 1, 0, 0, 0])
    }

    /// A single black cell sums to 1 everywhere in its neighborhood, so code
    /// 20 leaves the row empty on the next step.
    func testK2R2SingleCellDies() {
        var row = [UInt8](repeating: 0, count: 9)
        row[4] = 1
        var program = K2R2CA(code: 20, width: 9, row: row)
        program.step()
        XCTAssertEqual(program.row(), [UInt8](repeating: 0, count: 9))
    }

    /// Every catalog reference is deterministic: two fresh programs hash the
    /// same after the same number of steps.
    func testCatalogReferencesAreDeterministic() {
        for spec in Catalog.all {
            var a = spec.makeProgram()
            var b = spec.makeProgram()
            for _ in 0..<16 {
                a.step()
                b.step()
            }
            XCTAssertEqual(RowHash.fnv1a(a.row()), RowHash.fnv1a(b.row()), spec.id)
        }
    }

    /// Pinned golden hashes, recorded from the reference implementations at
    /// `max(32, min(height, stepLimit))` steps. A change to a CPU program (or a
    /// mismatched GPU kernel) fails here.
    ///
    /// E90/E22 share a hash and E150/E105 share a hash: at *even* steps the
    /// rule-22/90 pair and the rule-105/150 complement pair coincide (they
    /// differ at odd steps). That is a real property of the rules, not a bug.
    func testGoldenRowHashes() {
        let goldens: [(id: String, steps: Int, hash: UInt64)] = [
            ("E250", 160, 3454988026751882156),
            ("E109", 160, 1328108264670897272),
            ("E190", 160, 10937494152029502636),
            ("T600", 300, 2514265377707847661),
            ("T1329", 320, 3221449700774003980),
            ("T219", 160, 11725463326479794815),
            ("T957", 160, 11192566255924613452),
            ("T966", 160, 16101822695064495244),
            ("T1884", 160, 18321503795442451745),
            ("E30.block1100", 160, 615673218960636069),
            ("K2R2-20.seed195", 220, 13209351891583281257),
            ("T1329.seed916", 300, 2511403021277914069),
            ("E90", 200, 4778698135788584607),
            ("E22", 200, 4778698135788584607),
            ("E60", 200, 5503811919850749983),
            ("E150", 200, 2652570193100248716),
            ("E105", 200, 2652570193100248716),
            ("E129", 200, 7171463190519933580),
            ("E225", 300, 7499964040490707204),
            ("T237", 200, 2748416153078817951),
            ("T948", 200, 15347415833077877439),
            ("T1749", 200, 11906067471390591036),
            ("T420", 200, 14875601662526370927),
            ("E90.sparse", 200, 10108808006888323985),
            ("E126.pairs", 200, 4063800591829441653),
            ("E184.rand", 200, 14548386552639075464),
            ("E30", 200, 1521513059911051745),
            ("E45", 200, 16526704753940013665),
            ("E73", 200, 13798088140420961612),
            ("T177", 300, 8989692848850490165),
            ("T912", 300, 13411034643568056879),
            ("T2040", 300, 12986489760047039721),
            ("E90.rand", 200, 4299876937117059375),
            ("E22.rand", 200, 14849965979033566730),
            ("E22.seed19", 200, 15578877860320897447),
            ("E126.rand", 200, 13247624735719521465),
            ("E110", 400, 16141864199417367557),
            ("E54", 300, 17369092390066220023),
            ("T1041", 400, 3545670611698640313),
            ("T1635", 600, 5085765711341694157),
            ("T2049", 600, 18349513846607122993),
            ("T1599", 600, 14285951473571738455),
            ("E110.rand", 400, 2917164218058808844),
            ("T1329.seed54889", 400, 2758096440786442988),
            ("T357.seed28", 300, 7216418007845935533),
        ]
        XCTAssertEqual(goldens.count, Catalog.all.count)
        for golden in goldens {
            let spec = Catalog.spec(id: golden.id)!
            XCTAssertEqual(
                RowHash.hash(of: spec, steps: golden.steps),
                golden.hash,
                "\(golden.id) @ \(golden.steps) steps"
            )
        }
    }
}
