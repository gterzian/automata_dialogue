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
            ("E28", 160, 6969119734906298988),
            ("E94", 200, 16163618331398585983),
            ("E77", 160, 3454988026751882156),
            ("E57", 160, 9154087072357564848),
            ("E54", 160, 12268134608263542188),
            ("E73", 200, 13798088140420961612),
            ("E2", 160, 14010142410009317932),
            ("T39", 160, 382802302921959660),
            ("T1677", 160, 2432797321085793101),
            ("T1500", 160, 6955124866482997172),
            ("T1047", 160, 15808485347260098436),
            ("T183", 160, 18292917516316392407),
            ("T600", 300, 2514265377707847661),
            ("T1329", 320, 3221449700774003980),
            ("T219", 160, 11725463326479794815),
            ("T957", 160, 11192566255924613452),
            ("T966", 160, 16101822695064495244),
            ("T1884", 160, 18321503795442451745),
            ("K2R2-62", 100, 17993234121373055900),
            ("E30.block1100", 160, 615673218960636069),
            ("K2R2-20.seed195", 220, 13209351891583281257),
            ("T1329.seed916", 300, 2511403021277914069),
            ("T357.seed28", 300, 7216418007845935533),
            ("E184.rand", 200, 14548386552639075464),
            ("E178.rand", 300, 7609675907030880946),
            ("E15.rand", 300, 13553952225296892793),
            ("E14.rand", 300, 280445754855110948),
            ("T1587.rand", 300, 17991707566955887459),
            ("E90", 200, 4778698135788584607),
            ("E22", 200, 4778698135788584607),
            ("E60", 200, 5503811919850749983),
            ("E150", 200, 2652570193100248716),
            ("E105", 200, 2652570193100248716),
            ("E129", 200, 7171463190519933580),
            ("E225", 300, 7499964040490707204),
            ("E18", 200, 4778698135788584607),
            ("E126", 200, 7635705133642641663),
            ("T237", 200, 2748416153078817951),
            ("T948", 200, 15347415833077877439),
            ("T1749", 200, 11906067471390591036),
            ("T420", 200, 14875601662526370927),
            ("T561", 200, 9202371232136777983),
            ("T399", 200, 937986798358805375),
            ("T1182", 200, 13505668091381044364),
            ("T1419", 200, 12170222562854053500),
            ("T1848", 200, 14928805390958838437),
            ("T1932", 200, 12552551727187232609),
            ("T885", 200, 15729522712992327689),
            ("T1284", 200, 7162540317396076312),
            ("T453", 200, 13957502309512361116),
            ("T1509", 200, 12158663148630329285),
            ("T273", 200, 2652570193100248716),
            ("T1410", 200, 4290425064472565780),
            ("K2R2-2", 100, 4778698135788584607),
            ("K2R2-30", 100, 431827701342135263),
            ("K2R2-42", 100, 6630362196662299020),
            ("E30", 200, 1521513059911051745),
            ("E45", 200, 16526704753940013665),
            ("T177", 300, 8989692848850490165),
            ("T912", 300, 13411034643568056879),
            ("T2040", 300, 12986489760047039721),
            ("T138", 300, 1507773758218080352),
            ("T867", 300, 7404740519303322239),
            ("T1473", 300, 718588134473388999),
            ("T1929", 300, 14015654936781484921),
            ("T777", 300, 13331332587056806735),
            ("K2R2-10", 100, 17703342702506015727),
            ("K2R2-50", 100, 6671344886566794471),
            ("E90.rand", 200, 4299876937117059375),
            ("E22.rand", 200, 14849965979033566730),
            ("E22.seed19", 200, 15578877860320897447),
            ("E126.rand", 200, 13247624735719521465),
            ("E126.pairs", 200, 4063800591829441653),
            ("E90.sparse", 200, 10108808006888323985),
            ("E150.rand", 300, 17938947903626467662),
            ("E18.rand", 300, 13511024128808811235),
            ("E60.rand", 300, 543776073197978169),
            ("E232.rand", 300, 29236326512687648),
            ("E170.rand", 300, 12348410137824240500),
            ("E2.rand", 300, 11225442691826979348),
            ("T237.rand", 300, 3168710069207365525),
            ("T1182.rand", 300, 10501947482677482773),
            ("E110", 400, 16141864199417367557),
            ("E110.rand", 400, 2917164218058808844),
            ("E54.rand", 300, 17369092390066220023),
            ("E106.rand", 300, 10386610955894224192),
            ("E154.rand", 300, 1525231850699887762),
            ("E62", 400, 720204220533466843),
            ("T1041", 400, 3545670611698640313),
            ("T1635", 600, 5085765711341694157),
            ("T2049", 600, 18349513846607122993),
            ("T1599", 600, 14285951473571738455),
            ("T1662", 400, 15957426853843696369),
            ("T1329.seed54889", 400, 2758096440786442988),
            ("T1635.rand", 400, 12475035497438195144),
            ("T2049.rand", 400, 16277026613124459383),
            ("T2046.rand", 400, 5541600489560257083),
            ("T1329.rand", 400, 16339617077237975729),
            ("T357.rand", 400, 16086306413163457767),
            ("T948.rand", 400, 3665512894805767804),
            ("T1920.rand", 400, 2721162654831873753),
            ("T219.rand", 400, 10771223916520041877),
            ("K2R2-52.rand", 400, 7397607101063065959),
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
