# Curated Inventory of Cellular Automata

Source: Wolfram, *A New Kind of Science*, chapter 3 (elementary rules and 3-color totalistic rules), with rule numbering and totalistic coding checked against the Wolfram Atlas, MathWorld and the Wolfram code definition.

Every entry keeps visible structure over a few hundred steps and carries four things: its **type** (repetition, nesting, randomness, complex localized structures), a short account of **how it looks and evolves**, its **start** condition, and its **algorithm** as a Swift `Program` for the harness (`RowProgram` + `SpaceTime`, see `harness-design.md`).

**IDs.** `E<n>` is elementary rule *n* (2 colors, nearest neighbors). `T<n>` is 3-color totalistic code *n*. **Equivalents.** Mirror images and black/white swaps of a rule give the same picture up to that transform (a swap changes the background). They are listed as *Variants*.

**Extension: initial conditions.** Each entry now also reports what the rule does from three kinds of start: **S** a single cell (the original view), **P** a repeating block (a repetitive, non-random row) and **R** a random row. The random start also gives the Wolfram class (1 uniform, 2 simple structures, 3 random-looking, 4 localized structures that move and interact). The extension draws on chapter 6 of *A New Kind of Science* (starting from randomness) and on the Wolfram Atlas organization of each rule (single cell, numbered seeds, random rows with different densities, difference patterns, ring cycle lengths). Section 1.4 defines the starts and their engine code, section 1.6 collects the chapter's findings, section 7 adds rules from chapter 6, section 8 lists every rule in one matrix, section 9 cross-tabulates single-cell type against class and section 10 records the checks.

---

## 1. Shared engines

### 1.1 Elementary CA (Wolfram code)

The neighborhood `(l, c, r)` is read as the 3-bit number `n = 4l + 2c + r`. The new cell is bit `n` of the rule number (bit 7 ↔ `111`, bit 0 ↔ `000`). Edges wrap, which suits a board wider than the pattern (width ≥ 2 × steps + 1 for a single-cell start).

```swift
public struct ElementaryCA: RowProgram {
    public enum Start { case centerCell, rightmostCell, random(seed: UInt64) }

    public let width: Int
    public let rule: UInt8
    private var cells: [UInt8]
    private var scratch: [UInt8]

    public init(rule: UInt8, width: Int, start: Start) {
        self.rule = rule
        self.width = width
        var row = [UInt8](repeating: 0, count: width)
        switch start {
        case .centerCell:    row[width / 2] = 1
        case .rightmostCell: row[width - 1] = 1
        case .random(let seed):
            var rng = SplitMix64(seed: seed)          // SPCore PRNG
            for i in 0..<width { row[i] = UInt8(rng.next() & 1) }
        }
        cells = row
        scratch = row
    }

    public mutating func step() {
        for i in 0..<width {
            let l = cells[(i + width - 1) % width]
            let c = cells[i]
            let r = cells[(i + 1) % width]
            scratch[i] = (rule >> ((l << 2) | (c << 1) | r)) & 1
        }
        swap(&cells, &scratch)
    }

    public func row() -> [UInt8] { cells }
}
```

Each entry below also gives a closed Boolean form of its local rule. A unit test can assert that the form agrees with the table for all 8 neighborhoods.

### 1.2 Totalistic CA, k colors, radius 1

The new color depends only on the **sum** of the three cell values `l + c + r`, which runs from `0` to `3(k − 1)` (0…6 for 3 colors). The rule's **code** is a base-k number with `3(k − 1) + 1` digits. Digit `s` (counted from the right, starting at 0) is the new color for sum `s`. Code 777 in base 3 is `1001210`, so sum 0 → 0, sum 1 → 1, sum 2 → 2, sum 3 → 1, sum 4 → 0, sum 5 → 0, sum 6 → 1.

```swift
public struct TotalisticCA: RowProgram {
    public let width: Int
    public let colors: Int
    public let code: Int
    private let table: [UInt8]          // table[s] = new color for neighborhood sum s
    private var cells: [UInt8]
    private var scratch: [UInt8]

    public init(code: Int, colors: Int = 3, width: Int, startColor: UInt8 = 1) {
        self.code = code
        self.colors = colors
        self.width = width
        var t = [UInt8]()
        var rest = code
        for _ in 0..<(3 * (colors - 1) + 1) {
            t.append(UInt8(rest % colors))      // digit s of the code in base k
            rest /= colors
        }
        table = t
        var row = [UInt8](repeating: 0, count: width)
        row[width / 2] = startColor             // single gray cell for 3 colors
        cells = row
        scratch = row
    }

    public mutating func step() {
        for i in 0..<width {
            let s = Int(cells[(i + width - 1) % width]) + Int(cells[i]) + Int(cells[(i + 1) % width])
            scratch[i] = table[s]
        }
        swap(&cells, &scratch)
    }

    public func row() -> [UInt8] { cells }
}
```

**Implementation notes for totalistic rules**

- The table has `(2r + 1)(k − 1) + 1` entries for radius `r`, so the rule space is `k^((2r+1)(k−1)+1)`: 16 rules for k = 2, r = 1; 2187 for k = 3, r = 1; 64 for k = 2, r = 2.
- Precompute the table once from the code; the step loop is one sum and one lookup per cell.
- Codes divisible by 3 map sum 0 to color 0, so an empty (white) background stays empty. All `T` entries below have this property.
- Palette: index 0 white, 1 gray, 2 black. Frames carry the indices (`GridFrame.stateCount = 3`) and the output applies the palette.
- Some elementary rules are totalistic too, with outputs that depend only on the sum: rule 150 (odd sum), rule 22 (sum = 1), rule 254 (sum ≥ 1), rule 232 (sum ≥ 2).
- 2D outer-totalistic rules (Life-like) use the same idea with the center cell kept separate: table index = `centerState * (maxNeighborSum + 1) + neighborSum`.

### 1.3 Catalog registration

```swift
.init(id: "E90", title: "Rule 90", behavior: .nesting) {
    SpaceTime(ElementaryCA(rule: 90, width: 401, start: .centerCell), height: 200)
},
.init(id: "T1329", title: "3-color totalistic 1329", behavior: .repetition) {
    SpaceTime(TotalisticCA(code: 1329, width: 301), height: 200)
},
```


### 1.4 Initial conditions: simple, repetitive, random

Every inventory entry is studied from three kinds of start. The Wolfram Atlas organizes each rule the same way: *Simple initial conditions* (a single black cell and the first 100 numbered seeds), *Random initial conditions* (a perfectly random row, rows with different probabilities of black, difference patterns) and *Finite size properties* (cycle lengths on rings). Chapter 6 supplies the theory that connects the three.

| Code | Start | Atlas section | Engine value | What it reveals |
| --- | --- | --- | --- | --- |
| **S** | simple: one non-white cell in a white row; Atlas seed *n* writes the base-2 (base-3 for 3 colors) digits of *n* on white | Single black cell, First 100 initial conditions | `.single`, `.number(n)` | the rule's own behavior type (repetition, nesting, randomness, complex structures) |
| **P** | repetitive: a fixed block of cells repeated across the whole row | (chapter 6, p.267) | `.block([...])` | periodic dynamics; each block evolves like a ring of its own size |
| **R** | random: every cell chosen independently, black with probability *p* (p = ½ is the perfectly random row) | Perfectly random, Different probabilities of black, Difference patterns | `.random(seed:density:)` | the rule's class (1–4), its information handling, its density |

Entries cite their evidence with two tags: `[ch6]` for statements made in the chapter (page given), `[sim]` for values measured for this inventory (rows of 1000–3000 cells with wrap-around, 300–1500 steps, several seeds). A statement that carries both was reproduced by simulation.

```swift
/// Initial conditions shared by all one-dimensional engines.
public enum InitialCondition {
    /// One non-white cell: S. `rightmost` pins it to the right edge (rule 110).
    case single(color: UInt8 = 1, rightmost: Bool = false)
    /// A block repeated across the board: P. Choose a width that is a multiple of the
    /// block length so the wrap-around edge continues the pattern.
    case block([UInt8])
    /// Random row: R. Each cell is non-white with probability `density`; the non-white
    /// color is uniform. `nil` gives the uniform distribution over all colors
    /// (density ½ for 2 colors, ⅔ for 3 colors).
    case random(seed: UInt64, density: Double? = nil)
    /// Atlas seed number: the digits of `n` in `base`, most significant first, written
    /// on white starting at the center cell: S'.
    case number(Int, base: Int = 2)
}

extension InitialCondition {
    public func row(width: Int, colors: Int) -> [UInt8] {
        var row = [UInt8](repeating: 0, count: width)
        switch self {
        case .single(let color, let rightmost):
            row[rightmost ? width - 1 : width / 2] = color
        case .block(let b):
            for i in 0..<width { row[i] = b[i % b.count] }
        case .random(let seed, let density):
            var rng = SplitMix64(seed: seed)                       // SPCore PRNG
            let p = density ?? Double(colors - 1) / Double(colors)
            for i in 0..<width {
                let u = Double(rng.next() >> 11) / 9_007_199_254_740_992.0   // 2^53
                if u < p { row[i] = UInt8(1 + Int(rng.next() % UInt64(colors - 1))) }
            }
        case .number(let n, let base):
            var digits = [UInt8](); var rest = n
            while rest > 0 { digits.append(UInt8(rest % base)); rest /= base }
            let start = width / 2
            for (i, d) in digits.reversed().enumerated() where start + i < width { row[start + i] = d }
        }
        return row
    }
}

// Same file as ElementaryCA / TotalisticCA, so the extensions reach their private storage.
extension ElementaryCA {
    public init(rule: UInt8, width: Int, initial: InitialCondition) {
        self.init(rule: rule, width: width, start: .centerCell)
        let row = initial.row(width: width, colors: 2)
        cells = row
        scratch = row
    }
}

extension TotalisticCA {
    public init(code: Int, colors: Int = 3, width: Int, initial: InitialCondition) {
        self.init(code: code, colors: colors, width: width)
        let row = initial.row(width: width, colors: colors)
        cells = row
        scratch = row
    }
}
```

A unit test per start kind: `.single` has exactly one non-zero cell at `width / 2`; `.block([1, 0])` equals `[1, 0, 1, 0, …]`; `.random(seed: s)` is reproducible and its mean converges to `density`; `.number(19)` gives `10011` starting at the center.

### 1.5 Catalog registration for start conditions

The entries of sections 2–5 keep their original registration (S, or R for E54). The extension adds two optional fields, so the three-argument form above keeps working with `start: .simple` and `wolframClass: nil`:

```swift
public enum StartKind { case simple, repetitive, random }
public enum WolframClass { case class1, class2, class3, class4 }

// IDs: "E30" is the original entry; "E30.P" and "E30.R" are its repetitive and random starts.
.init(id: "E30.R", title: "Rule 30, random start", behavior: .randomness,
      start: .random, wolframClass: .class3) {
    SpaceTime(ElementaryCA(rule: 30, width: 400, initial: .random(seed: 30)), height: 300)
},
.init(id: "T1329.R", title: "3-color totalistic 1329, random start", behavior: .repetition,
      start: .random, wolframClass: .class4) {
    SpaceTime(TotalisticCA(code: 1329, width: 400, initial: .random(seed: 1329)), height: 400)
},
```

`behavior` records the type seen from the single cell (the four types of the original inventory); `wolframClass` records the class seen from random rows. The two are independent labels (see the cross-table in section 9).

### 1.6 What the chapter says about starts

**The four classes (random starts).** Wolfram found in 1983 that random rows lead to four kinds of behavior:

| Class | Final behavior from random rows | Information about the initial row | Effect of changing one initial cell |
| --- | --- | --- | --- |
| 1 | one uniform state, the same for almost every row | forgotten | the change dies out |
| 2 | a set of simple structures that stay fixed or repeat every few steps | kept locally | the change persists in a small region |
| 3 | random-looking, with triangles and small structures at every scale | communicated over long range | the change spreads at a uniform rate through the whole system |
| 4 | localized structures that move and interact | communicated only when a moving structure carries it | the change spreads sporadically |

Class 4 sits between 2 and 3 in activity: class 1 and 2 systems settle into states with almost no further activity, class 3 keeps many cells changing at every step, and class 4 wavers between them. Neighboring rules in a sequence tend to share a class. Four-color examples in the chapter run class 1, then 2, then 4, then 3 (ch6 p.240–241). Continuous cellular automata (ch6 p.242–244) and two-dimensional ones (Game of Life, ch6 p.249) show the same classes, with class 4 at the transitions.

**Frequencies and special cases.** For symmetric 2-color nearest-neighbor rules that keep an all-white row white, the chapter pictures all 32 rules (ch6 p.232): `0, 32, 128, 160, 250, 254` are class 1; `4, 36, 72, 76, 94, 104, 108, 132, 164, 178, 200, 204, 218, 222, 232, 236, 50` are class 2 (the chapter's grid shows them as frozen stripes and periodic structures); `18, 22, 90, 122, 126, 146, 150, 182` are class 3; `54` is class 4 (the other class 4 elementary rule, 110, is not symmetric). Rules in the first two columns of that page can only produce class 1 or 2.

**Single cell versus random row.** The type from a single cell does not determine the class:

- T600 and T1329 repeat from one gray cell and are class 4 from random rows.
- Rule 22 is nested from one cell and class 3 from a random row; rule 90 is nested from one cell and class 3 from a random row; rules 18, 146 and 218 are nested from one cell (the rule-90 picture) and class 3, 3 and 2 from random rows.
- Rule 54 is a plain checkerboard from one cell and class 4 from a random row.

**Where randomness comes from.** Rule 30 and rule 22 generate randomness: with one cell or with a random row their large-scale statistics match (rule 30 away from its left edge, ch6 p.261), and a low initial density is forgotten. Rule 90 is additive, so its randomness is inherited from the initial row: any finite seed gives a nested superposition of the single-cell pattern, and a low initial density comes back at steps 2ⁿ (ch6 p.264–265). The Atlas "different probabilities of black" panels show this difference directly.

| Rule | Row density after 100–1000 steps from p = 0.05 `[sim]` | Reading |
| --- | --- | --- |
| 90, 60 | ≈ 0.10 at steps 2ⁿ, ≈ 0.50 between | inherited |
| 150, 105 | ≈ 0.14 at steps 2ⁿ, ≈ 0.50 between | inherited |
| 22 | ≈ 0.35 | generated |
| 30, 45 | ≈ 0.50 | generated |
| 126, 129 | ≈ 0.50 | generated |
| 182 | ≈ 0.75 | generated |
| 18, 146 | ≈ 0.25 | generated |
| 122 | ≈ 0.50 | generated |

**Repetitive starts and ring size.** A fixed block of n cells repeated forever evolves like a ring of n cells, so the pattern repeats with period at most 2ⁿ (ch6 p.267). Any finite ring is periodic (ch6 p.258). Maximum periods grow quickly in class 3 and moderately in class 4: rule 90 reaches 2^((n−1)/2) − 1 (single cell, n = 19: 511, n = 23: 2047), rule 30 grows like 2^(0.63n) (1455 at n = 15), rule 45 gets within 86 % of 2ⁿ (463 347 935 at n = 29), and rule 110 peaks roughly like n³ (ch6 p.259–260; the rule 90 and rule 30 values were reproduced `[sim]`). For rule 30 the shortest repeating blocks are (period, block size): (1, 1), (1, 2), (3, 12), (4, 7), (5, 5), (6, 84), (7, 15), (8, 4), (9, 15), (10, 155); no block gives period 2, and a block of 275 cells gives period 11 (ch6 p.268). Rule 30 yields repetition only from a repeated block (ch6 p.267), while other rules, rule 126 among them, also have repetitive starts that use two different blocks.

**Special starts that make a rule imitate another.** Rule 126 behaves like rule 90 from rows made of 2-cell blocks `00` and `11` (ch6 p.269). Rule 90 and rule 150 follow themselves on blocks of two cells, which produces their nesting (ch6 p.270–271). Rule 184 does the same with nested seeds (ch6 p.272). Rule 22 turns random from the numbered seeds 19, 25, 37, 38, 39, 41, 45, 47, 51, 57, 61, … (ch6 p.263 note, reproduced `[sim]`).

**Persistent structures of class 4 rules.** Testing numbered seeds finds the structures that a class 4 rule supports (ch6 p.281–289): code 20 with 2 colors and next-nearest neighbors (section 7.3) produces nothing for most small seeds, a period-22 structure from seeds 195 and 219, and moving structures from larger ones; code 357 first shows structure at seed 28; code 1329 shows stationary structures, a moving one at seed 916, and unbounded growth at seeds 54 889, 97 439, 115 396, 166 426 and 2 069 116 (the width grows roughly linearly, `[sim]`). Rule 110 has persistent structures labeled (a)–(n) on its regular background, and a 41-cell block inserted in the background gives unbounded growth (ch6 p.292–293).

---

## 2. Simple repetition

### E250 — Rule 250 (checkerboard triangle)

- **Look:** a single cell widens into a triangle at one cell per step. The interior fills with a fine checkerboard that flips every step, bounded by two sharp diagonals.
- **Start:** `.centerCell`. **Local rule:** `l | r`.
- **Variants:** 160.

```swift
.init(id: "E250", title: "Rule 250", behavior: .repetition) {
    SpaceTime(ElementaryCA(rule: 250, width: 321, start: .centerCell), height: 160)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | repetition | Triangle of checkerboard (see **Look**). Any short seed on white behaves the same way: the black spreads one cell per step on both sides. |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `10` → periodic: pattern repeats every 2 cells, time period 2; `110` → uniform black after 1 step; `100` → uniform black after 2 steps; `1100` → uniform black after 1 step. |
| R random | **class 1** | Every random row ends **uniformly black** in a few steps (≈ 4–7 on a 64-cell ring): a cell turns black when either neighbor is. Chapter 6 lists 250 with 0, 32 and 160 as rules that reach a uniform state (p.224). Nothing changes afterwards, and a changed initial cell leaves no trace. |

**Atlas rule properties.** Equivalents — mirror: itself, black/white swap: 160, mirror + swap: 160. Algebraic form (mod 2, p = left, q = center, r = right): `p + r + pr`.

```swift
.init(id: "E250.P", title: "Rule 250, block 10", behavior: .repetition,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(ElementaryCA(rule: 250, width: 400, initial: .block([1, 0])), height: 200)
},
.init(id: "E250.R", title: "Rule 250, random start", behavior: .repetition,
      start: .random, wolframClass: .class1) {
    SpaceTime(ElementaryCA(rule: 250, width: 400, initial: .random(seed: 250)), height: 300)
}
```

### E109 — Rule 109 (striped field, repeating triangles)

- **Look:** the empty background alternates black and white every step, which draws horizontal stripes across the whole screen. Inside, a growing triangle holds a lattice of small interlocking triangle motifs that repeat in a fixed pattern.
- **Start:** `.centerCell`. **Local rule:** table `01101101` (000 → 1, 111 → 0).
- **Variants:** 73 is its black/white swap.

```swift
.init(id: "E109", title: "Rule 109", behavior: .repetition) {
    SpaceTime(ElementaryCA(rule: 109, width: 321, start: .centerCell), height: 160)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | repetition | Repetitive triangle on the flickering background (see **Look**). Its black/white swap 73 gives the random-looking picture of E73 from the same single cell. |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `10` → uniform, flips white/black every step after 1 step; `110` → uniform, flips white/black every step after 1 step; `100` → static pattern `100` repeating every 3 cells; `1100` → static pattern `1100` repeating every 4 cells. |
| R random | **class 2** | Patches of periodic structure on the flickering background (≈ 32 % of cells change per step; small rings settle with periods 6–144). A changed cell stays inside a region ≈ 25 cells wide, so patches evolve independently. |

**Atlas rule properties.** Equivalents — mirror: itself, black/white swap: 73, mirror + swap: 73. Algebraic form (mod 2, p = left, q = center, r = right): `1 + p + r + pq + qr + pqr`.

```swift
.init(id: "E109.P", title: "Rule 109, block 1100", behavior: .repetition,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(ElementaryCA(rule: 109, width: 400, initial: .block([1, 1, 0, 0])), height: 200)
},
.init(id: "E109.R", title: "Rule 109, random start", behavior: .repetition,
      start: .random, wolframClass: .class2) {
    SpaceTime(ElementaryCA(rule: 109, width: 400, initial: .random(seed: 109)), height: 300)
}
```

### E190 — Rule 190 (black triangle with diagonal stripes)

- **Look:** a solid black triangle expands at full speed, crossed by evenly spaced diagonal white stripes that run parallel to one edge.
- **Start:** `.centerCell`. **Local rule:** table `10111110`.

```swift
.init(id: "E190", title: "Rule 190", behavior: .repetition) {
    SpaceTime(ElementaryCA(rule: 190, width: 321, start: .centerCell), height: 160)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | repetition | Black triangle with diagonal stripes (see **Look**). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `10` → uniform black after 1 step; `110` → periodic: pattern repeats every 3 cells, time period 3; `100` → uniform black after 1 step; `1100` → periodic: pattern repeats every 4 cells, time period 4 after 1 step. |
| R random | **class 2** | Black dominates (≈ 83 %). The whole row drifts left one cell per step, so an n-cell ring repeats with period n. A changed cell becomes a 1–3 cell wide defect that rides left at full speed forever: localized but persistent. |

**Atlas rule properties.** Equivalents — mirror: 246, black/white swap: 130, mirror + swap: 144. Algebraic form (mod 2, p = left, q = center, r = right): `p + q + r + pr + qr`.

```swift
.init(id: "E190.P", title: "Rule 190, block 1100", behavior: .repetition,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(ElementaryCA(rule: 190, width: 400, initial: .block([1, 1, 0, 0])), height: 200)
},
.init(id: "E190.R", title: "Rule 190, random start", behavior: .repetition,
      start: .random, wolframClass: .class2) {
    SpaceTime(ElementaryCA(rule: 190, width: 400, initial: .random(seed: 190)), height: 300)
}
```

### T600 — 3-color totalistic 600 (fixed-width column of triangles)

- **Look:** a single gray cell grows into a narrow column of stacked, textured triangles. The width stays constant while the same bands recur down the screen.
- **Start:** single gray cell. **Variants (same behavior class in the chapter):** 843, 1086.

```swift
.init(id: "T600", title: "3-color totalistic 600", behavior: .repetition) {
    SpaceTime(TotalisticCA(code: 600, width: 161), height: 300)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | repetition | Fixed-width textured column (see **Look**). Single-cell behavior is repetitive, yet the rule is class 4 from random rows. |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `12` → periodic: pattern repeats every 2 cells, time period 2; `120` → uniform gray after 1 step; `10` → periodic: pattern repeats every 2 cells, time period 4; `2110` → periodic: pattern repeats every 4 cells, time period 6 after 1 step (1 = gray, 2 = black). |
| R random | **class 4** | Listed among the class 4 rules with 3 colors (ch6 note, p.235). In runs the board turns mostly white (≈ 87 %) with sparse persistent structures that interact; a change spreads about 100 cells and no further `[sim]`. |

**Rule table** (neighborhood sum 0…6 → new color): `0 2 0 1 1 2 0`.

```swift
.init(id: "T600.P", title: "3-color totalistic 600, block 2110", behavior: .repetition,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(TotalisticCA(code: 600, width: 400, initial: .block([2, 1, 1, 0])), height: 200)
},
.init(id: "T600.R", title: "3-color totalistic 600, random start", behavior: .repetition,
      start: .random, wolframClass: .class4) {
    SpaceTime(TotalisticCA(code: 600, width: 400, initial: .random(seed: 600)), height: 300)
}
```

### T1329 — 3-color totalistic 1329 (period 78)

- **Look:** a column of fixed width with large gray-and-black triangular bands. The whole pattern repeats exactly every 78 steps, the longest period among the fixed-size 3-color totalistic rules in the chapter.
- **Start:** single gray cell. **Check:** after a short transient, the trimmed row at step *t* equals the trimmed row at *t − 78* (confirmed by simulation: first repeat at t = 110 matching t = 32).

```swift
.init(id: "T1329", title: "3-color totalistic 1329", behavior: .repetition) {
    SpaceTime(TotalisticCA(code: 1329, width: 161), height: 320)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | repetition | Fixed-width column repeating every 78 steps (see **Look**). Other seeds (base-3 digits of the seed number, `.number(n, base: 3)`) show the structure zoo of ch6 `[ch6, verified]`: the smallest ones are stationary, seed 916 gives the first moving structure (width stays 17–30), and seeds 54 889, 97 439, 115 396, 166 426 and 2 069 116 grow without bound (width grows roughly linearly, 0.5–1 cell per step). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `12` → periodic: pattern repeats every 2 cells, time period 2; `120` → uniform gray after 1 step; `10` → periodic: pattern repeats every 2 cells, time period 4; `2110` → uniform gray after 4 steps (1 = gray, 2 = black). |
| R random | **class 4** | Class 4 (ch6 p.282): persistent structures on a mostly white board (≈ 82 % white, ≈ 18 % of cells change per step `[sim]`); changes stay within ≈ 10 cells in the runs. Small rings repeat with period 78 or 232 or stay fixed `[sim]`. |

**Rule table** (neighborhood sum 0…6 → new color): `0 2 0 1 1 2 1`.

```swift
.init(id: "T1329.P", title: "3-color totalistic 1329, block 10", behavior: .repetition,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(TotalisticCA(code: 1329, width: 400, initial: .block([1, 0])), height: 200)
},
.init(id: "T1329.R", title: "3-color totalistic 1329, random start", behavior: .repetition,
      start: .random, wolframClass: .class4) {
    SpaceTime(TotalisticCA(code: 1329, width: 400, initial: .random(seed: 1329)), height: 300)
}
```

### T219 — 3-color totalistic 219 (vertical-striped triangle)

- **Look:** a triangle grows at full speed. A regular comb of thin vertical lines fills its interior, spaced evenly and unchanging.
- **Start:** single gray cell.

```swift
.init(id: "T219", title: "3-color totalistic 219", behavior: .repetition) {
    SpaceTime(TotalisticCA(code: 219, width: 321), height: 160)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | repetition | Triangle with a comb of vertical lines (see **Look**). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `12` → periodic: pattern repeats every 2 cells, time period 2 after 1 step; `120` → uniform white after 2 steps; `10` → static pattern `10` repeating every 2 cells; `2110` → periodic: pattern repeats every 4 cells, time period 2 after 1 step (1 = gray, 2 = black). |
| R random | **class 2 or 4** | The chapter calls it borderline, either class 2 or class 4 (p.240). In runs the board freezes in ≤ 8 steps into mostly white (≈ 93 %) with static black lines; a change dies or stays 2 cells wide `[sim]`. |

**Rule table** (neighborhood sum 0…6 → new color): `0 1 0 2 2 0 0`.

```swift
.init(id: "T219.P", title: "3-color totalistic 219, block 2110", behavior: .repetition,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(TotalisticCA(code: 219, width: 400, initial: .block([2, 1, 1, 0])), height: 200)
},
.init(id: "T219.R", title: "3-color totalistic 219, random start", behavior: .repetition,
      start: .random, wolframClass: .class2) {
    SpaceTime(TotalisticCA(code: 219, width: 400, initial: .random(seed: 219)), height: 300)
}
```

### T957 — 3-color totalistic 957 (fine lattice triangle)

- **Look:** a clean triangle filled edge to edge with a tiny, regular lattice texture, like woven cloth.
- **Start:** single gray cell.

```swift
.init(id: "T957", title: "3-color totalistic 957", behavior: .repetition) {
    SpaceTime(TotalisticCA(code: 957, width: 321), height: 160)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | repetition | Fine lattice triangle (see **Look**). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `12` → periodic: pattern repeats every 2 cells, time period 4; `120` → uniform, cycles through colors with period 2 after 1 step; `10` → uniform, cycles through colors with period 2 after 1 step; `2110` → uniform, cycles through colors with period 2 after 5 steps (1 = gray, 2 = black). |
| R random | **class 3** | Random mix of all three colors, ≈ 74 % of cells change per step; a change spreads both ways (±140–200 after 300 steps). |

**Rule table** (neighborhood sum 0…6 → new color): `0 1 1 2 2 0 1`.

```swift
.init(id: "T957.P", title: "3-color totalistic 957, block 12", behavior: .repetition,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(TotalisticCA(code: 957, width: 400, initial: .block([1, 2])), height: 200)
},
.init(id: "T957.R", title: "3-color totalistic 957, random start", behavior: .repetition,
      start: .random, wolframClass: .class3) {
    SpaceTime(TotalisticCA(code: 957, width: 400, initial: .random(seed: 957)), height: 300)
}
```

### T966 — 3-color totalistic 966 (striped core)

- **Look:** a triangle whose edges carry a fine lattice while the middle shows dense horizontal banding split by a vertical seam.
- **Start:** single gray cell.

```swift
.init(id: "T966", title: "3-color totalistic 966", behavior: .repetition) {
    SpaceTime(TotalisticCA(code: 966, width: 321), height: 160)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | repetition | Striped triangle with a vertical seam (see **Look**). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `12` → uniform, cycles through colors with period 2 after 2 steps; `120` → uniform, cycles through colors with period 2 after 1 step; `10` → uniform, cycles through colors with period 2 after 3 steps; `2110` → uniform, cycles through colors with period 2 after 1 step (1 = gray, 2 = black). |
| R random | **class 2** | Gray and black in equal shares, almost all cells flip every step (period 2 pattern); a change either vanishes or stays in a block ≈ 90 cells wide. |

**Rule table** (neighborhood sum 0…6 → new color): `0 1 2 2 2 0 1`.

```swift
.init(id: "T966.P", title: "3-color totalistic 966, block 12", behavior: .repetition,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(TotalisticCA(code: 966, width: 400, initial: .block([1, 2])), height: 200)
},
.init(id: "T966.R", title: "3-color totalistic 966, random start", behavior: .repetition,
      start: .random, wolframClass: .class2) {
    SpaceTime(TotalisticCA(code: 966, width: 400, initial: .random(seed: 966)), height: 300)
}
```

### T1884 — 3-color totalistic 1884 (dark scale pattern)

- **Look:** a dark-textured triangle filled with a regular arched, scale-like lattice in black and gray.
- **Start:** single gray cell.

```swift
.init(id: "T1884", title: "3-color totalistic 1884", behavior: .repetition) {
    SpaceTime(TotalisticCA(code: 1884, width: 321), height: 160)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | repetition | Dark scale lattice (see **Look**). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `12` → static pattern `12` repeating every 2 cells; `120` → uniform white after 1 step; `10` → static pattern `12` repeating every 2 cells after 1 step; `2110` → uniform black after 2 steps (1 = gray, 2 = black). |
| R random | **class 3** | Mostly black (≈ 61 %) random mix, ≈ 46 % of cells change per step; changes spread both ways (±230 after 300 steps). |

**Rule table** (neighborhood sum 0…6 → new color): `0 1 2 0 2 1 2`.

```swift
.init(id: "T1884.P", title: "3-color totalistic 1884, block 12", behavior: .repetition,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(TotalisticCA(code: 1884, width: 400, initial: .block([1, 2])), height: 200)
},
.init(id: "T1884.R", title: "3-color totalistic 1884, random start", behavior: .repetition,
      start: .random, wolframClass: .class3) {
    SpaceTime(TotalisticCA(code: 1884, width: 400, initial: .random(seed: 1884)), height: 300)
}
```

---

## 3. Nesting (fractal)

### E90 — Rule 90 (Sierpinski triangle)

- **Look:** a single cell grows into the Sierpinski triangle: white triangular holes at every scale inside a black lace, symmetric left to right. Fractal dimension log₂3 ≈ 1.58.
- **Start:** `.centerCell`. **Local rule:** `l ^ r`.
- **Variants:** 165.

```swift
.init(id: "E90", title: "Rule 90", behavior: .nesting) {
    SpaceTime(ElementaryCA(rule: 90, width: 401, start: .centerCell), height: 200)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | nesting | Sierpinski triangle (see **Look**). Rule 90 is additive, so any initial row with black cells only in a limited region gives a nested pattern: at every step where a new white triangle starts in the center the whole pattern is two copies of the initial block (ch6 p.264, `[ch6]`). The first 100 Atlas seeds are all nested. |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `10` → uniform white after 1 step; `110` → static pattern `110` repeating every 3 cells; `100` → static pattern `011` repeating every 3 cells after 1 step; `1100` → uniform white after 2 steps. |
| R random | **class 3** | Random output with black density ½ and white triangles of all sizes (ch6 p.228). Additive, so a changed cell spreads both ways at full speed (±400 cells after 400 steps `[sim]`). The randomness is inherited from the initial row: from initial black density 0.05 the density comes back to ≈ 0.1 at steps 2ⁿ (256, 512, 1024) and sits near ½ in between (ch6 p.265 `[ch6]`, verified). |

**Atlas rule properties.** Equivalents — mirror: itself, black/white swap: 165, mirror + swap: 165. Algebraic form (mod 2, p = left, q = center, r = right): `p + r`.

```swift
.init(id: "E90.P", title: "Rule 90, block 110", behavior: .nesting,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(ElementaryCA(rule: 90, width: 399, initial: .block([1, 1, 0])), height: 200)
},
.init(id: "E90.R", title: "Rule 90, random start", behavior: .nesting,
      start: .random, wolframClass: .class3) {
    SpaceTime(ElementaryCA(rule: 90, width: 400, initial: .random(seed: 90)), height: 300)
}
```

### E22 — Rule 22

- **Look:** a symmetric nested triangle in the same family as rule 90, with slightly different detail inside the holes. Fractal dimension log₂3.
- **Start:** `.centerCell`. **Local rule:** `(l + c + r) == 1 ? 1 : 0`.
- **Variants:** 151.

```swift
.init(id: "E22", title: "Rule 22", behavior: .nesting) {
    SpaceTime(ElementaryCA(rule: 22, width: 401, start: .centerCell), height: 200)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | nesting | Nested (see **Look**), and so are the smallest seeds (binary seeds 1–18 stay nested, `[sim]`). Special seeds give rule-30-like randomness instead: the binary digit strings of 19, 25, 37, 38, 39, 41, 45, 47, 51, 57, 61, … produce a pattern with black density ≈ 0.35 whose random core widens at ≈ 0.766 cells per step, with repetitive regions on both sides (ch6 p.263 and its note `[ch6]`; compression test confirms randomness `[sim]`). Use `.number(19)` to see it. |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `10` → static pattern `10` repeating every 2 cells; `110` → uniform white after 1 step; `100` → uniform white after 2 steps; `1100` → periodic: pattern repeats every 4 cells, time period 2. |
| R random | **class 3** | Random with white triangles (ch6 p.227). Black density settles near **0.35** (measured 0.348; ch6 gives 0.35095). A changed cell spreads both ways at ≈ 0.77 cells per step (±302/306 after 400 steps `[sim]`; ch6 gives 0.766). The randomness is generated by the rule: a low initial density (0.05) is forgotten within about 100 steps (ch6 p.265, `[sim]`). |

**Atlas rule properties.** Equivalents — mirror: itself, black/white swap: 151, mirror + swap: 151. Algebraic form (mod 2, p = left, q = center, r = right): `p + q + r + pqr`.

```swift
.init(id: "E22.P", title: "Rule 22, block 1100", behavior: .nesting,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(ElementaryCA(rule: 22, width: 400, initial: .block([1, 1, 0, 0])), height: 200)
},
.init(id: "E22.R", title: "Rule 22, random start", behavior: .nesting,
      start: .random, wolframClass: .class3) {
    SpaceTime(ElementaryCA(rule: 22, width: 400, initial: .random(seed: 22)), height: 300)
}
```

### E60 — Rule 60 (one-sided Sierpinski)

- **Look:** a right-angled Sierpinski triangle that grows to one side, with a vertical edge on one side and a diagonal on the other.
- **Start:** `.centerCell`. **Local rule:** `l ^ c`.
- **Variants:** 102 (mirror), 153, 195.

```swift
.init(id: "E60", title: "Rule 60", behavior: .nesting) {
    SpaceTime(ElementaryCA(rule: 60, width: 401, start: .centerCell), height: 200)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | nesting | One-sided Sierpinski triangle (see **Look**). Additive like rule 90: finite seeds give superpositions of this pattern. |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `10` → uniform white after 2 steps; `110` → periodic: pattern repeats every 3 cells, time period 3; `100` → periodic: pattern repeats every 3 cells, time period 3 after 1 step; `1100` → uniform white after 3 steps. |
| R random | **class 3** | Random with density ½. Additive like rule 90 but one-sided: a change spreads only to the right at speed 1. The randomness is inherited: low initial density 0.05 returns to ≈ 0.1 at steps 256 and 512 `[sim]`. |

**Atlas rule properties.** Equivalents — mirror: 102, black/white swap: 195, mirror + swap: 153. Algebraic form (mod 2, p = left, q = center, r = right): `p + q`.

```swift
.init(id: "E60.P", title: "Rule 60, block 110", behavior: .nesting,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(ElementaryCA(rule: 60, width: 399, initial: .block([1, 1, 0])), height: 200)
},
.init(id: "E60.R", title: "Rule 60, random start", behavior: .nesting,
      start: .random, wolframClass: .class3) {
    SpaceTime(ElementaryCA(rule: 60, width: 400, initial: .random(seed: 60)), height: 300)
}
```

### E150 — Rule 150 (dense nested lattice)

- **Look:** a symmetric triangle with a busier nested structure: small branching tree-like clusters inside larger triangular voids. Fractal dimension log₂(1 + √5) ≈ 1.69.
- **Start:** `.centerCell`. **Local rule:** `l ^ c ^ r`.

```swift
.init(id: "E150", title: "Rule 150", behavior: .nesting) {
    SpaceTime(ElementaryCA(rule: 150, width: 401, start: .centerCell), height: 200)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | nesting | Dense nested lattice (see **Look**). Additive, and one of the rare rules whose blocks of cells evolve like single cells, which is why it stays nested (ch6 p.271 `[ch6]`). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `10` → static pattern `10` repeating every 2 cells; `110` → uniform white after 1 step; `100` → uniform black after 1 step; `1100` → periodic: pattern repeats every 4 cells, time period 2. |
| R random | **class 3** | Random with density exactly ½ (ch6 note p.226). Additive: a change spreads both ways at speed 1. Inherited randomness: initial density 0.05 returns to ≈ 0.14 at steps 2ⁿ `[sim]`. Rings of 64 cells repeat with period 32 in the runs `[sim]`. |

**Atlas rule properties.** Equivalents — mirror: itself, black/white swap: itself, mirror + swap: itself. Algebraic form (mod 2, p = left, q = center, r = right): `p + q + r`.

```swift
.init(id: "E150.P", title: "Rule 150, block 1100", behavior: .nesting,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(ElementaryCA(rule: 150, width: 400, initial: .block([1, 1, 0, 0])), height: 200)
},
.init(id: "E150.R", title: "Rule 150, random start", behavior: .nesting,
      start: .random, wolframClass: .class3) {
    SpaceTime(ElementaryCA(rule: 150, width: 400, initial: .random(seed: 150)), height: 300)
}
```

### E105 — Rule 105 (nested pattern on a striped field)

- **Look:** the nested structure of rule 150 in inverted form. The background alternates black and white each step, drawing horizontal stripes, and the fractal triangle sits within it.
- **Start:** `.centerCell`. **Local rule:** `1 ^ l ^ c ^ r`.

```swift
.init(id: "E105", title: "Rule 105", behavior: .nesting) {
    SpaceTime(ElementaryCA(rule: 105, width: 401, start: .centerCell), height: 200)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | nesting | Nested pattern on the striped field (see **Look**). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `10` → periodic: pattern repeats every 2 cells, time period 2; `110` → uniform, flips white/black every step after 1 step; `100` → uniform, flips white/black every step after 1 step; `1100` → static pattern `1100` repeating every 4 cells. |
| R random | **class 3** | Random (ch6 p.228), the color-inverted twin of 150: density ½, additive, full-speed spreading, inherited randomness (density 0.05 → ≈ 0.14 at steps 2ⁿ `[sim]`). |

**Atlas rule properties.** Equivalents — mirror: itself, black/white swap: itself, mirror + swap: itself. Algebraic form (mod 2, p = left, q = center, r = right): `1 + p + q + r`.

```swift
.init(id: "E105.P", title: "Rule 105, block 10", behavior: .nesting,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(ElementaryCA(rule: 105, width: 400, initial: .block([1, 0])), height: 200)
},
.init(id: "E105.R", title: "Rule 105, random start", behavior: .nesting,
      start: .random, wolframClass: .class3) {
    SpaceTime(ElementaryCA(rule: 105, width: 400, initial: .random(seed: 105)), height: 300)
}
```

### E129 — Rule 129 (white Sierpinski on black)

- **Look:** a solid black screen with an inverted Sierpinski triangle in white whose holes show black at every scale.
- **Start:** `.centerCell`. **Local rule:** `(l == c && c == r) ? 1 : 0`. The empty background turns black after the first step (000 → 1) and stays black (111 → 1).
- **Variants:** 126 (black Sierpinski on white): `(l | c | r) & ~(l & c & r)`.

```swift
.init(id: "E129", title: "Rule 129", behavior: .nesting) {
    SpaceTime(ElementaryCA(rule: 129, width: 401, start: .centerCell), height: 200)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | nesting | Sierpinski triangle on black (see **Look**). Rule 126 (its swap) gives the same nested picture from a single cell because, started from 2-cell blocks (`00`/`11`), it behaves exactly like rule 90 on every other step (ch6 p.269 `[ch6]`). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `10` → uniform black after 2 steps; `110` → uniform black after 2 steps; `100` → uniform black after 2 steps; `1100` → uniform black after 2 steps. |
| R random | **class 3** | Equivalent to rule 126, which the chapter shows never settling down (ch6 p.226): density ½, triangles of all sizes. A changed cell spreads both ways at nearly full speed. A low initial density is forgotten (0.05 → ≈ ½ by step 256 `[sim]`). With special rows made of 2-cell blocks it acts like rule 90 (ch6 p.269); with another special two-block mixture it acts like a simple class 2 rule (ch6 p.267). |

**Atlas rule properties.** Equivalents — mirror: itself, black/white swap: 126, mirror + swap: 126. Algebraic form (mod 2, p = left, q = center, r = right): `1 + p + q + r + pq + pr + qr`.

```swift
.init(id: "E129.P", title: "Rule 129, block 10", behavior: .nesting,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(ElementaryCA(rule: 129, width: 400, initial: .block([1, 0])), height: 200)
},
.init(id: "E129.R", title: "Rule 129, random start", behavior: .nesting,
      start: .random, wolframClass: .class3) {
    SpaceTime(ElementaryCA(rule: 129, width: 400, initial: .random(seed: 129)), height: 300)
}
```

### E225 — Rule 225 (narrow nested band)

- **Look:** a nested pattern confined to a diagonal band. Its width grows only like the square root of the number of steps, so the picture is a thin fractal ribbon sliding across a black field.
- **Start:** `.centerCell`. **Local rule:** `1 ^ l ^ (c | r)` (the negation of rule 30's rule).
- **Variants:** 106, 120, 169.

```swift
.init(id: "E225", title: "Rule 225", behavior: .nesting) {
    SpaceTime(ElementaryCA(rule: 225, width: 401, start: .centerCell), height: 300)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | nesting | Thin nested ribbon (see **Look**). With other simple seeds the chapter reports a much more complicated pattern, and with a periodic background plus one inserted white cell a largely random pattern that expands one cell per step (ch6 note, p.263 `[ch6]`; the block symbol is lost in the PDF text layer). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `10` → periodic: pattern repeats every 2 cells, time period 2; `110` → periodic: pattern repeats every 3 cells, time period 3; `100` → uniform black after 2 steps; `1100` → periodic: pattern repeats every 4 cells, time period 2 after 1 step. |
| R random | **class 3** | Random, density ½; no periodic state on 64-cell rings within 6000 steps. Disturbances travel right at speed 1 and never left, leaving a random region behind them. |

**Atlas rule properties.** Equivalents — mirror: 169, black/white swap: 120, mirror + swap: 106. Algebraic form (mod 2, p = left, q = center, r = right): `1 + p + q + r + qr`.

```swift
.init(id: "E225.P", title: "Rule 225, block 110", behavior: .nesting,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(ElementaryCA(rule: 225, width: 399, initial: .block([1, 1, 0])), height: 200)
},
.init(id: "E225.R", title: "Rule 225, random start", behavior: .nesting,
      start: .random, wolframClass: .class3) {
    SpaceTime(ElementaryCA(rule: 225, width: 400, initial: .random(seed: 225)), height: 300)
}
```

### T237 — 3-color totalistic 237

- **Look:** a Sierpinski-like triangle with large white holes and fine gray detail, the most common nested form among the 3-color rules (the chapter groups 237 and 948 as the two most common).
- **Start:** single gray cell.

```swift
.init(id: "T237", title: "3-color totalistic 237", behavior: .nesting) {
    SpaceTime(TotalisticCA(code: 237, width: 401), height: 200)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | nesting | Sierpinski-like triangle (see **Look**). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `12` → uniform white after 3 steps; `120` → uniform white after 2 steps; `10` → uniform white after 4 steps; `2110` → uniform white after 2 steps (1 = gray, 2 = black). |
| R random | **class 3** | Only white and black survive (gray disappears within the transient) in equal shares, ≈ 49 % of cells change per step; a change spreads both ways at full speed (±294 after 300 steps), like the additive 2-color rules. |

**Rule table** (neighborhood sum 0…6 → new color): `0 1 2 2 2 0 0`.

```swift
.init(id: "T237.P", title: "3-color totalistic 237, block 12", behavior: .nesting,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(TotalisticCA(code: 237, width: 400, initial: .block([1, 2])), height: 200)
},
.init(id: "T237.R", title: "3-color totalistic 237, random start", behavior: .nesting,
      start: .random, wolframClass: .class3) {
    SpaceTime(TotalisticCA(code: 237, width: 400, initial: .random(seed: 237)), height: 300)
}
```

### T948 — 3-color totalistic 948

- **Look:** nested triangles whose interiors branch into small tree-shaped motifs, giving a leafier fractal than T237.
- **Start:** single gray cell.

```swift
.init(id: "T948", title: "3-color totalistic 948", behavior: .nesting) {
    SpaceTime(TotalisticCA(code: 948, width: 401), height: 200)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | nesting | Leafy nested triangle (see **Look**). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `12` → periodic: pattern repeats every 2 cells, time period 2 after 1 step; `120` → uniform, cycles through colors with period 2 after 1 step; `10` → static pattern `10` repeating every 2 cells; `2110` → uniform white after 6 steps (1 = gray, 2 = black). |
| R random | **class 3** | Mostly white (≈ 66 %), ≈ 31 % of cells change per step; a change spreads both ways at ≈ 0.5 cells per step. |

**Rule table** (neighborhood sum 0…6 → new color): `0 1 0 2 2 0 1`.

```swift
.init(id: "T948.P", title: "3-color totalistic 948, block 12", behavior: .nesting,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(TotalisticCA(code: 948, width: 400, initial: .block([1, 2])), height: 200)
},
.init(id: "T948.R", title: "3-color totalistic 948, random start", behavior: .nesting,
      start: .random, wolframClass: .class3) {
    SpaceTime(TotalisticCA(code: 948, width: 400, initial: .random(seed: 948)), height: 300)
}
```

### T1749 — 3-color totalistic 1749

- **Look:** nested triangles with solid black triangular voids at several scales, which gives the pattern more weight and contrast than the Sierpinski forms.
- **Start:** single gray cell.

```swift
.init(id: "T1749", title: "3-color totalistic 1749", behavior: .nesting) {
    SpaceTime(TotalisticCA(code: 1749, width: 401), height: 200)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | nesting | Nested triangle with black voids (see **Look**). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `12` → periodic: pattern repeats every 2 cells, time period 2; `120` → uniform gray after 1 step; `10` → periodic: pattern repeats every 2 cells, time period 2; `2110` → periodic: pattern repeats every 4 cells, time period 2 (1 = gray, 2 = black). |
| R random | **class 3** | Mixed colors, ≈ 63 % of cells change per step; changes spread both ways at full speed. |

**Rule table** (neighborhood sum 0…6 → new color): `0 1 2 1 0 1 2`.

```swift
.init(id: "T1749.P", title: "3-color totalistic 1749, block 2110", behavior: .nesting,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(TotalisticCA(code: 1749, width: 400, initial: .block([2, 1, 1, 0])), height: 200)
},
.init(id: "T1749.R", title: "3-color totalistic 1749, random start", behavior: .nesting,
      start: .random, wolframClass: .class3) {
    SpaceTime(TotalisticCA(code: 1749, width: 400, initial: .random(seed: 1749)), height: 300)
}
```

### T420 — 3-color totalistic 420

- **Look:** a sparser nested triangle with large clean white regions and a branching rhythm that differs from the 2-color forms (the one structure the chapter calls new among nested 3-color rules).
- **Start:** single gray cell.

```swift
.init(id: "T420", title: "3-color totalistic 420", behavior: .nesting) {
    SpaceTime(TotalisticCA(code: 420, width: 401), height: 200)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | nesting | Sparse nested triangle (see **Look**). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `12` → static pattern `12` repeating every 2 cells; `120` → uniform white after 1 step; `10` → static pattern `21` repeating every 2 cells after 1 step; `2110` → periodic: pattern repeats every 4 cells, time period 2 after 1 step (1 = gray, 2 = black). |
| R random | **class 3** | All three colors in equal shares (≈ ⅓ each), ≈ 67 % of cells change per step; changes spread at full speed in both directions. |

**Rule table** (neighborhood sum 0…6 → new color): `0 2 1 0 2 1 0`.

```swift
.init(id: "T420.P", title: "3-color totalistic 420, block 2110", behavior: .nesting,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(TotalisticCA(code: 420, width: 400, initial: .block([2, 1, 1, 0])), height: 200)
},
.init(id: "T420.R", title: "3-color totalistic 420, random start", behavior: .nesting,
      start: .random, wolframClass: .class3) {
    SpaceTime(TotalisticCA(code: 420, width: 400, initial: .random(seed: 420)), height: 300)
}
```

---

## 4. Randomness

### E30 — Rule 30

- **Look:** the left edge is a clean diagonal line. The rest is a disordered tangle of black and white with scattered white triangles of every size. The center column is statistically random (Wolfram's random number generator).
- **Start:** `.centerCell`. **Local rule:** `l ^ (c | r)`.
- **Variants:** 86, 135 (black background), 149 (black background).

```swift
.init(id: "E30", title: "Rule 30", behavior: .randomness) {
    SpaceTime(ElementaryCA(rule: 30, width: 401, start: .centerCell), height: 200)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | randomness | Random-looking pattern with a clean left edge (see **Look**). Away from that edge it is almost indistinguishable from the random-start pattern (ch6 p.261 `[ch6]`), which shows that the rule generates its own randomness. |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `10` → static pattern `10` repeating every 2 cells; `110` → uniform white after 3 steps; `100` → uniform white after 2 steps; `1100` → periodic: pattern repeats every 4 cells, time period 8 after 1 step. |
| R random | **class 3** | Random with density ½ (ch6 p.227, p.261). A change spreads right at speed 1 and left at ≈ 0.2–0.3 cells per step. Intrinsic randomness: a low initial density is forgotten at once (0.05 → 0.5 by step 100 `[sim]`). On n-cell rings from a single cell the period grows like 2^(0.63 n): 1455, 6016, 10 846, 2844, 247, 3420, 597 for n = 15…21 (ch6 p.259, reproduced `[sim]`). |

**Atlas rule properties.** Equivalents — mirror: 86, black/white swap: 135, mirror + swap: 149. Algebraic form (mod 2, p = left, q = center, r = right): `p + q + r + qr`.

```swift
.init(id: "E30.P", title: "Rule 30, block 1100", behavior: .randomness,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(ElementaryCA(rule: 30, width: 400, initial: .block([1, 1, 0, 0])), height: 200)
},
.init(id: "E30.R", title: "Rule 30, random start", behavior: .randomness,
      start: .random, wolframClass: .class3) {
    SpaceTime(ElementaryCA(rule: 30, width: 400, initial: .random(seed: 30)), height: 300)
}
```

### E45 — Rule 45

- **Look:** a regular diagonal on one side and a mix of short vertical dashes and irregular blocks filling the rest, with fewer triangular voids than rule 30. Horizontal stripes cover the background.
- **Start:** `.centerCell`. **Local rule:** `l ^ (c | (1 - r))`.
- **Variants:** 75, 89, 101.

```swift
.init(id: "E45", title: "Rule 45", behavior: .randomness) {
    SpaceTime(ElementaryCA(rule: 45, width: 401, start: .centerCell), height: 200)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | randomness | Random-looking pattern (see **Look**). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `10` → uniform, flips white/black every step after 1 step; `110` → periodic: pattern repeats every 3 cells, time period 3; `100` → static pattern `100` repeating every 3 cells; `1100` → uniform, flips white/black every step after 3 steps. |
| R random | **class 3** | Random with density ½. Disturbances spread right at speed 1; the left edge advances ≈ 0.17 cells per step (ch6 note). Finite rings hold the longest periods of all elementary rules: close to 2ⁿ, e.g. 463 347 935 for n = 29, 86 % of the maximum (ch6 p.260). |

**Atlas rule properties.** Equivalents — mirror: 101, black/white swap: 75, mirror + swap: 89. Algebraic form (mod 2, p = left, q = center, r = right): `1 + p + r + qr`.

```swift
.init(id: "E45.P", title: "Rule 45, block 110", behavior: .randomness,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(ElementaryCA(rule: 45, width: 399, initial: .block([1, 1, 0])), height: 200)
},
.init(id: "E45.R", title: "Rule 45, random start", behavior: .randomness,
      start: .random, wolframClass: .class3) {
    SpaceTime(ElementaryCA(rule: 45, width: 400, initial: .random(seed: 45)), height: 300)
}
```

### E73 — Rule 73

- **Look:** a symmetric triangle of fine, dotted, speckled texture with no long diagonals, giving a smoother grain than rules 30 and 45. Horizontal stripes cover the background.
- **Start:** `.centerCell`. **Local rule:** table `01001001`.
- **Variants:** 109, its black/white swap. From a single black cell on white, rule 109 produces the repetitive picture in E109 while rule 73 produces this one.

```swift
.init(id: "E73", title: "Rule 73", behavior: .randomness) {
    SpaceTime(ElementaryCA(rule: 73, width: 401, start: .centerCell), height: 200)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | randomness | Fine speckled triangle (see **Look**). Its swap 109 gives the repetitive picture of E109. |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `10` → uniform, flips white/black every step after 1 step; `110` → static pattern `110` repeating every 3 cells; `100` → uniform, flips white/black every step after 1 step; `1100` → static pattern `1100` repeating every 4 cells. |
| R random | **class 2** | Random start gives patches of periodic structure on the flickering background (≈ 32 % of cells change per step; rings of 64 cells settle with periods 10–90). A change stays within ≈ 10 cells: **class 2**; the single-cell picture is speckled. |

**Atlas rule properties.** Equivalents — mirror: itself, black/white swap: 109, mirror + swap: 109. Algebraic form (mod 2, p = left, q = center, r = right): `1 + p + q + r + pr + pqr`.

```swift
.init(id: "E73.P", title: "Rule 73, block 1100", behavior: .randomness,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(ElementaryCA(rule: 73, width: 400, initial: .block([1, 1, 0, 0])), height: 200)
},
.init(id: "E73.R", title: "Rule 73, random start", behavior: .randomness,
      start: .random, wolframClass: .class2) {
    SpaceTime(ElementaryCA(rule: 73, width: 400, initial: .random(seed: 73)), height: 300)
}
```

### T177 — 3-color totalistic 177

- **Look:** a triangle whose entire interior is a gray-and-black scatter with no regular structure, bounded by clean diagonals.
- **Start:** single gray cell.

```swift
.init(id: "T177", title: "3-color totalistic 177", behavior: .randomness) {
    SpaceTime(TotalisticCA(code: 177, width: 601), height: 300)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | randomness | Random gray-black scatter (see **Look**). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `12` → periodic: pattern repeats every 2 cells, time period 4; `120` → uniform white after 1 step; `10` → periodic: pattern repeats every 2 cells, time period 4 after 1 step; `2110` → periodic: pattern repeats every 4 cells, time period 2 after 1 step (1 = gray, 2 = black). |
| R random | **class 3** | Random mix (43 % white), ≈ 68 % of cells change per step; changes spread both ways at ≈ 0.85 cells per step. |

**Rule table** (neighborhood sum 0…6 → new color): `0 2 1 0 2 0 0`.

```swift
.init(id: "T177.P", title: "3-color totalistic 177, block 12", behavior: .randomness,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(TotalisticCA(code: 177, width: 400, initial: .block([1, 2])), height: 200)
},
.init(id: "T177.R", title: "3-color totalistic 177, random start", behavior: .randomness,
      start: .random, wolframClass: .class3) {
    SpaceTime(TotalisticCA(code: 177, width: 400, initial: .random(seed: 177)), height: 300)
}
```

### T912 — 3-color totalistic 912

- **Look:** a mostly random interior with a visible grain of small triangles, and a more regular band along the edges.
- **Start:** single gray cell.

```swift
.init(id: "T912", title: "3-color totalistic 912", behavior: .randomness) {
    SpaceTime(TotalisticCA(code: 912, width: 601), height: 300)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | randomness | Random interior with triangle grain (see **Look**). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `12` → uniform white after 4 steps; `120` → uniform white after 1 step; `10` → uniform white after 5 steps; `2110` → uniform white after 4 steps (1 = gray, 2 = black). |
| R random | **class 3** | Random mix, ≈ 63 % of cells change per step; changes spread both ways at ≈ 0.65 cells per step. |

**Rule table** (neighborhood sum 0…6 → new color): `0 1 2 0 2 0 1`.

```swift
.init(id: "T912.P", title: "3-color totalistic 912, block 12", behavior: .randomness,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(TotalisticCA(code: 912, width: 400, initial: .block([1, 2])), height: 200)
},
.init(id: "T912.R", title: "3-color totalistic 912, random start", behavior: .randomness,
      start: .random, wolframClass: .class3) {
    SpaceTime(TotalisticCA(code: 912, width: 400, initial: .random(seed: 912)), height: 300)
}
```

### T2040 — 3-color totalistic 2040

- **Look:** random texture broken by dark triangular patches of solid black of various sizes.
- **Start:** single gray cell.

```swift
.init(id: "T2040", title: "3-color totalistic 2040", behavior: .randomness) {
    SpaceTime(TotalisticCA(code: 2040, width: 601), height: 300)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | randomness | Random texture with black patches (see **Look**). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `12` → periodic: pattern repeats every 2 cells, time period 2; `120` → uniform white after 1 step; `10` → periodic: pattern repeats every 2 cells, time period 2 after 1 step; `2110` → static pattern `2112` repeating every 4 cells after 2 steps (1 = gray, 2 = black). |
| R random | **class 3** | Random mix, ≈ 54 % of cells change per step; changes spread both ways at ≈ 0.8 cells per step. |

**Rule table** (neighborhood sum 0…6 → new color): `0 2 1 0 1 2 2`.

```swift
.init(id: "T2040.P", title: "3-color totalistic 2040, block 12", behavior: .randomness,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(TotalisticCA(code: 2040, width: 400, initial: .block([1, 2])), height: 200)
},
.init(id: "T2040.R", title: "3-color totalistic 2040, random start", behavior: .randomness,
      start: .random, wolframClass: .class3) {
    SpaceTime(TotalisticCA(code: 2040, width: 400, initial: .random(seed: 2040)), height: 300)
}
```

---

## 5. Complex localized structures

### E110 — Rule 110

- **Look:** from a single cell the pattern grows to one side. A regular background of small triangles forms, and localized structures of many sizes travel through it at different speeds and collide in intricate ways. The left part settles into a regular lattice while the active region keeps producing new structures. Rule 110 is computationally universal.
- **Start:** `.rightmostCell`, view pinned to the right so the pattern grows leftward (as in the earlier Rust experiment). **Local rule:** `(c | r) & ~(l & c & r) & 1`.
- **Variants:** 124 (mirror), 137, 193.

```swift
.init(id: "E110", title: "Rule 110", behavior: .complexity) {
    SpaceTime(ElementaryCA(rule: 110, width: 1201, start: .rightmostCell), height: 400)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | complexity | Growing, rule-110 background with moving structures (see **Look**). The structures live on the regular triangle background (ch6 `[ch6]`). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `10` → uniform white after 2 steps; `110` → uniform white after 2 steps; `100` → uniform white after 3 steps; `1100` → periodic: pattern repeats every 4 cells, time period 2 after 1 step. |
| R random | **class 4** | Quickly organizes into a regular background of small triangles crossed by localized structures that move and collide (ch6 p.229–230, 700 steps per page). A change spreads only when a moving structure carries it: sporadic, ≈ 150–240 cells wide after 400 steps `[sim]` (ch6 p.250–252). Finite-ring periods peak roughly like n³ (ch6 p.260). The chapter catalogs persistent structures found from blocks narrower than 40 cells. |

**Atlas rule properties.** Equivalents — mirror: 124, black/white swap: 137, mirror + swap: 193. Algebraic form (mod 2, p = left, q = center, r = right): `q + r + qr + pqr`.

```swift
.init(id: "E110.P", title: "Rule 110, block 1100", behavior: .complexity,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(ElementaryCA(rule: 110, width: 400, initial: .block([1, 1, 0, 0])), height: 200)
},
.init(id: "E110.R", title: "Rule 110, random start", behavior: .complexity,
      start: .random, wolframClass: .class4) {
    SpaceTime(ElementaryCA(rule: 110, width: 400, initial: .random(seed: 110)), height: 300)
}
```

### E54 — Rule 54 (random start)

- **Look:** from a single cell the picture is a plain checkerboard triangle. From a random row it develops a regular background crossed by moving localized structures that collide and interact. Chapter 6 of the book studies it; chapter 3 does not show it.
- **Start:** `.random(seed:)`. **Local rule:** `c ^ (l | r)`.
- **Variants:** 147.

```swift
.init(id: "E54", title: "Rule 54, random start", behavior: .complexity) {
    SpaceTime(ElementaryCA(rule: 54, width: 400, start: .random(seed: 54)), height: 300)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | complexity | Plain checkerboard triangle (see **Look**): from one cell nothing interesting happens, the complexity appears from random rows. |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `10` → uniform white after 2 steps; `110` → uniform white after 3 steps; `100` → uniform white after 2 steps; `1100` → periodic: pattern repeats every 4 cells, time period 2. |
| R random | **class 4** | Regular background plus moving, colliding structures (ch6 grid, p.232). A change spreads sporadically: both edges advance ≈ 0.553 cells per step on average (ch6 note), and some changes die out; the rest cover ≈ 320–450 cells after 400 steps `[sim]`. |

**Atlas rule properties.** Equivalents — mirror: itself, black/white swap: 147, mirror + swap: 147. Algebraic form (mod 2, p = left, q = center, r = right): `p + q + r + pr`.

```swift
// the original E54 registration above is already the random start (E54.R)
.init(id: "E54.S", title: "Rule 54, single cell", behavior: .repetition,
      start: .simple, wolframClass: .class4) {
    SpaceTime(ElementaryCA(rule: 54, width: 401, start: .centerCell), height: 200)
},
.init(id: "E54.P", title: "Rule 54, block 1100", behavior: .complexity,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(ElementaryCA(rule: 54, width: 400, initial: .block([1, 1, 0, 0])), height: 200)
},
```

### T1041 — 3-color totalistic 1041

- **Look:** a growing triangle that fills with a mixture of regular stripes and irregular regions; the chapter reports that the pattern becomes repetitive after about 150 steps.
- **Start:** single gray cell.

```swift
.init(id: "T1041", title: "3-color totalistic 1041", behavior: .complexity) {
    SpaceTime(TotalisticCA(code: 1041, width: 801), height: 400)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | complexity | Stripes plus irregular regions, repetitive after about 150 steps (see **Look**). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `12` → periodic: pattern repeats every 2 cells, time period 4; `120` → uniform, cycles through colors with period 2 after 1 step; `10` → periodic: pattern repeats every 2 cells, time period 4; `2110` → periodic: pattern repeats every 4 cells, time period 2 after 1 step (1 = gray, 2 = black). |
| R random | **class 4** | Class 4 in the chapter's note (p.235). In runs most of the board falls into a gray/black flicker with sparse defects (≈ 91 % of cells change each step); changes die out or stay within ≈ 50 cells `[sim]`. |

**Rule table** (neighborhood sum 0…6 → new color): `0 2 1 2 0 1 1`.

```swift
.init(id: "T1041.P", title: "3-color totalistic 1041, block 12", behavior: .complexity,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(TotalisticCA(code: 1041, width: 400, initial: .block([1, 2])), height: 200)
},
.init(id: "T1041.R", title: "3-color totalistic 1041, random start", behavior: .complexity,
      start: .random, wolframClass: .class4) {
    SpaceTime(TotalisticCA(code: 1041, width: 400, initial: .random(seed: 1041)), height: 300)
}
```

### T1635 — 3-color totalistic 1635

- **Look:** black triangular regions of many sizes separated by textured, irregular zones, with localized structures crossing between them. After 3000 steps the chapter finds the long-term outcome still unclear.
- **Start:** single gray cell. Run to 3000 steps with a ring buffer and `stepsPerFrame` ≥ 10.

```swift
.init(id: "T1635", title: "3-color totalistic 1635", behavior: .complexity) {
    SpaceTime(TotalisticCA(code: 1635, width: 6101), height: 600)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | complexity | Black triangles and textured zones (see **Look**). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `12` → periodic: pattern repeats every 2 cells, time period 4; `120` → uniform white after 1 step; `10` → periodic: pattern repeats every 2 cells, time period 4 after 1 step; `2110` → periodic: pattern repeats every 4 cells, time period 2 after 1 step (1 = gray, 2 = black). |
| R random | **class 4** | Class 4 (ch6 note, p.235). Mostly black (≈ 68 %), ≈ 37 % of cells change per step; changes spread sporadically (≈ 220 cells after 400 steps `[sim]`). |

**Rule table** (neighborhood sum 0…6 → new color): `0 2 1 0 2 0 2`.

```swift
.init(id: "T1635.P", title: "3-color totalistic 1635, block 12", behavior: .complexity,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(TotalisticCA(code: 1635, width: 400, initial: .block([1, 2])), height: 200)
},
.init(id: "T1635.R", title: "3-color totalistic 1635, random start", behavior: .complexity,
      start: .random, wolframClass: .class4) {
    SpaceTime(TotalisticCA(code: 1635, width: 400, initial: .random(seed: 1635)), height: 300)
}
```

### T2049 — 3-color totalistic 2049

- **Look:** a large solid black wedge near the center flanked by long vertical lines, with a busy, irregular fringe of small structures along both outer sides. Its long-term outcome is also unclear after 3000 steps.
- **Start:** single gray cell. Run to 3000 steps.

```swift
.init(id: "T2049", title: "3-color totalistic 2049", behavior: .complexity) {
    SpaceTime(TotalisticCA(code: 2049, width: 6101), height: 600)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | complexity | Black wedge with busy fringes (see **Look**). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `12` → periodic: pattern repeats every 2 cells, time period 2; `120` → uniform white after 1 step; `10` → uniform black after 1 step; `2110` → static pattern `1221` repeating every 4 cells after 3 steps (1 = gray, 2 = black). |
| R random | **class 4** | Class 4 (ch6 note, p.235). Mostly black (≈ 63 %), ≈ 32 % of cells change per step; sporadic spreading, ≈ 150 cells each way after 300 steps `[sim]`. |

**Rule table** (neighborhood sum 0…6 → new color): `0 2 2 0 1 2 2`.

```swift
.init(id: "T2049.P", title: "3-color totalistic 2049, block 12", behavior: .complexity,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(TotalisticCA(code: 2049, width: 400, initial: .block([1, 2])), height: 200)
},
.init(id: "T2049.R", title: "3-color totalistic 2049, random start", behavior: .complexity,
      start: .random, wolframClass: .class4) {
    SpaceTime(TotalisticCA(code: 2049, width: 400, initial: .random(seed: 2049)), height: 300)
}
```

### T1599 — 3-color totalistic 1599 (the long transient)

- **Look:** from one gray cell the pattern grows irregularly for thousands of steps, reaching a width of roughly 670 cells (measured). Growth then slows, regions inside die out, and bursts of growth recur. At step 8282 it resolves into 31 simple repetitive structures.
- **Start:** single gray cell. Run to at least 8300 steps; a 1001-cell board with a ring buffer holds the whole pattern.
- **Check:** the live region stays near 670 cells wide through steps 4000–8600 in simulation, and the chapter gives 8282 as the resolution step.

```swift
.init(id: "T1599", title: "3-color totalistic 1599", behavior: .complexity) {
    SpaceTime(TotalisticCA(code: 1599, width: 1001), height: 600)
}
```

**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | complexity | Long transient resolving at step 8282 (see **Look**). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `12` → periodic: pattern repeats every 2 cells, time period 4 after 1 step; `120` → uniform black after 1 step; `10` → periodic: pattern repeats every 2 cells, time period 4; `2110` → periodic: pattern repeats every 4 cells, time period 2 after 1 step (1 = gray, 2 = black). |
| R random | **class 4** | Class 4 (ch6 note, p.235). Mostly white (≈ 69 %), ≈ 37 % of cells change per step; sporadic spreading, ≈ 110 cells each way after 300 steps `[sim]`. |

**Rule table** (neighborhood sum 0…6 → new color): `0 2 0 2 1 0 2`.

```swift
.init(id: "T1599.P", title: "3-color totalistic 1599, block 12", behavior: .complexity,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(TotalisticCA(code: 1599, width: 400, initial: .block([1, 2])), height: 200)
},
.init(id: "T1599.R", title: "3-color totalistic 1599, random start", behavior: .complexity,
      start: .random, wolframClass: .class4) {
    SpaceTime(TotalisticCA(code: 1599, width: 400, initial: .random(seed: 1599)), height: 300)
}
```

---

## 6. Summary

| Type | Elementary | 3-color totalistic |
| --- | --- | --- |
| Repetition | 250, 109, 190 | 600, 1329, 219, 957, 966, 1884 |
| Nesting | 90, 22, 60, 150, 105, 129, 225 | 237, 948, 1749, 420 |
| Randomness | 30, 45, 73 | 177, 912, 2040 |
| Complex localized structures | 110, 54 (random start) | 1041, 1635, 2049, 1599 |

Total: 32 entries.

Extended total: 32 original entries, 15 elementary rules added in section 7 (E254, E160, E4, E108, E232, E218, E94, E184, E50, E178, E18, E146, E122, E126, E182), class 1 stragglers E0, E32 and E128 (compact table), one 2-color radius-2 rule (K2R2-20) and 14 more 3-color codes in the compact table of 7.4.

---

## 7. Additional rules from chapter 6

Rules that the chapter pictures or discusses and that section 2–5 did not list. They fill the two classes that single-cell starts rarely show: class 1 (uniform final states) and class 2 (simple frozen or periodic structures), and add class 3 rules whose single-cell picture is nested. Entries follow the section 2–5 layout; each carries the same initial-conditions block.

### 7.1 Class 1 rules

| Rule | Table | Black/white swap | P results (`10` / `110` / `100` / `1100`; W white, B black, F flicker, s static stripes, p periodic) | Steps to uniform on a 64-cell random ring `[sim]` |
| --- | --- | --- | --- | --- |
| E0 | `00000000` | 255 | W / W / W / W | 1–1 |
| E32 | `00100000` | 251 | p / W / W / W | 2–4 |
| E128 | `10000000` | 254 | W / W / W / W | 3–5 |

All three lose a single cell in the first step and end in uniform white from random rows (ch6 p.224, `[sim]`). E254 and E160 below carry the full layout; E250 is in section 2.

### E254 — Rule 254 (solid black triangle)

- **Look:** a single cell widens into a solid black triangle at one cell per step on each side.
- **Start:** `.centerCell`. **Local rule:** table `11111110`; algebraic form `p + q + r + pq + pr + qr + pqr`.
- **Variants:** 128 (black/white swap), 128 (mirror + swap).

```swift
.init(id: "E254", title: "Rule 254", behavior: .repetition) {
    SpaceTime(ElementaryCA(rule: 254, width: 401, start: .centerCell), height: 200)
}
```


**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | repetition | Solid black triangle (see **Look**). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `10` → uniform black after 1 step; `110` → uniform black after 1 step; `100` → uniform black after 1 step; `1100` → uniform black after 1 step. |
| R random | **class 1** | Every white region of the random row fills with black from its edges, and the final state is **uniform black** (ch6 p.223–224, the opening example; rule 254 is the "either neighbor black" rule). On rings of 64 cells the final state arrives within 3 steps `[sim]`. A changed initial cell leaves no trace. |

**Atlas rule properties.** Equivalents — mirror: itself, black/white swap: 128, mirror + swap: 128. Algebraic form (mod 2, p = left, q = center, r = right): `p + q + r + pq + pr + qr + pqr`.

```swift
.init(id: "E254.P", title: "Rule 254, block 10", behavior: .repetition,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(ElementaryCA(rule: 254, width: 400, initial: .block([1, 0])), height: 200)
},
.init(id: "E254.R", title: "Rule 254, random start", behavior: .repetition,
      start: .random, wolframClass: .class1) {
    SpaceTime(ElementaryCA(rule: 254, width: 400, initial: .random(seed: 254)), height: 300)
}
```

### E160 — Rule 160 (vanishing cell)

- **Look:** a single cell disappears in the first step and the board stays white.
- **Start:** `.centerCell`. **Local rule:** table `10100000`; algebraic form `pr`.
- **Variants:** 250 (black/white swap), 250 (mirror + swap).

```swift
.init(id: "E160", title: "Rule 160", behavior: .repetition) {
    SpaceTime(ElementaryCA(rule: 160, width: 401, start: .centerCell), height: 200)
}
```


**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | repetition | The cell vanishes in one step (see **Look**); the board stays white. |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `10` → periodic: pattern repeats every 2 cells, time period 2; `110` → uniform white after 2 steps; `100` → uniform white after 1 step; `1100` → uniform white after 1 step. |
| R random | **class 1** | Uniform **white** final state (ch6 p.224, listed with 0, 32 and 250). Reached within 4–7 steps on a 64-cell ring `[sim]`; no change to the initial row survives. |

**Atlas rule properties.** Equivalents — mirror: itself, black/white swap: 250, mirror + swap: 250. Algebraic form (mod 2, p = left, q = center, r = right): `pr`.

```swift
.init(id: "E160.P", title: "Rule 160, block 10", behavior: .repetition,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(ElementaryCA(rule: 160, width: 400, initial: .block([1, 0])), height: 200)
},
.init(id: "E160.R", title: "Rule 160, random start", behavior: .repetition,
      start: .random, wolframClass: .class1) {
    SpaceTime(ElementaryCA(rule: 160, width: 400, initial: .random(seed: 160)), height: 300)
}
```

### 7.2 Class 2 and class 3 elementary rules

### E4 — Rule 4 (stable line)

- **Look:** a single cell stays put as a vertical black line forever.
- **Start:** `.centerCell`. **Local rule:** table `00000100`; algebraic form `q + pq + qr + pqr`.
- **Variants:** 223 (black/white swap), 223 (mirror + swap).

```swift
.init(id: "E4", title: "Rule 4", behavior: .repetition) {
    SpaceTime(ElementaryCA(rule: 4, width: 401, start: .centerCell), height: 200)
}
```


**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | repetition | One fixed vertical line (see **Look**). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `10` → static pattern `10` repeating every 2 cells; `110` → uniform white after 1 step; `100` → static pattern `100` repeating every 3 cells; `1100` → uniform white after 1 step. |
| R random | **class 2** | Class 2 with fixed structures only (ch6 p.225): every isolated black cell of the initial row becomes a vertical line, and the final state is a filtered copy of the initial row (black density ≈ 0.12 `[sim]`). A changed initial cell changes exactly one column, so information stays local (ch6 p.250). |

**Atlas rule properties.** Equivalents — mirror: itself, black/white swap: 223, mirror + swap: 223. Algebraic form (mod 2, p = left, q = center, r = right): `q + pq + qr + pqr`.

```swift
.init(id: "E4.P", title: "Rule 4, block 100", behavior: .repetition,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(ElementaryCA(rule: 4, width: 399, initial: .block([1, 0, 0])), height: 200)
},
.init(id: "E4.R", title: "Rule 4, random start", behavior: .repetition,
      start: .random, wolframClass: .class2) {
    SpaceTime(ElementaryCA(rule: 4, width: 400, initial: .random(seed: 4)), height: 300)
}
```

### E108 — Rule 108 (lines and blinkers)

- **Look:** a single cell stays put as a vertical black line forever.
- **Start:** `.centerCell`. **Local rule:** table `01101100`; algebraic form `q + pr`.
- **Variants:** 201 (black/white swap), 201 (mirror + swap).

```swift
.init(id: "E108", title: "Rule 108", behavior: .repetition) {
    SpaceTime(ElementaryCA(rule: 108, width: 401, start: .centerCell), height: 200)
}
```


**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | repetition | One fixed vertical line (see **Look**). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `10` → uniform white after 2 steps; `110` → uniform white after 2 steps; `100` → static pattern `100` repeating every 3 cells; `1100` → static pattern `1100` repeating every 4 cells. |
| R random | **class 2** | Class 2 (ch6 p.225, and the class 2 representative of the damage experiment on p.250): a random row freezes into vertical lines with period-2 flickers mixed in (black ≈ 32 %, ≈ 7 % of cells change per step `[sim]`). A changed cell leaves a difference confined to its own column. |

**Atlas rule properties.** Equivalents — mirror: itself, black/white swap: 201, mirror + swap: 201. Algebraic form (mod 2, p = left, q = center, r = right): `q + pr`.

```swift
.init(id: "E108.P", title: "Rule 108, block 1100", behavior: .repetition,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(ElementaryCA(rule: 108, width: 400, initial: .block([1, 1, 0, 0])), height: 200)
},
.init(id: "E108.R", title: "Rule 108, random start", behavior: .repetition,
      start: .random, wolframClass: .class2) {
    SpaceTime(ElementaryCA(rule: 108, width: 400, initial: .random(seed: 108)), height: 300)
}
```

### E232 — Rule 232 (majority vote)

- **Look:** a single cell vanishes after one step and the board stays white.
- **Start:** `.centerCell`. **Local rule:** table `11101000`; algebraic form `pq + pr + qr`.
- **Variants:** none.

```swift
.init(id: "E232", title: "Rule 232", behavior: .repetition) {
    SpaceTime(ElementaryCA(rule: 232, width: 401, start: .centerCell), height: 200)
}
```


**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | repetition | The cell vanishes in one step (see **Look**). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `10` → periodic: pattern repeats every 2 cells, time period 2; `110` → uniform black after 1 step; `100` → uniform white after 1 step; `1100` → static pattern `1100` repeating every 4 cells. |
| R random | **class 2** | Class 2 (ch6 p.225): the majority rule freezes a random row within ≈ 3 steps into solid vertical stripes of black and white, about half of each, and nothing changes afterwards `[sim]`. Each stripe is a copy of a run of the initial row that has two or more equal neighbors, so the output is a filtered version of the input. |

**Atlas rule properties.** Equivalents — mirror: itself, black/white swap: itself, mirror + swap: itself. Algebraic form (mod 2, p = left, q = center, r = right): `pq + pr + qr`.

```swift
.init(id: "E232.P", title: "Rule 232, block 10", behavior: .repetition,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(ElementaryCA(rule: 232, width: 400, initial: .block([1, 0])), height: 200)
},
.init(id: "E232.R", title: "Rule 232, random start", behavior: .repetition,
      start: .random, wolframClass: .class2) {
    SpaceTime(ElementaryCA(rule: 232, width: 400, initial: .random(seed: 232)), height: 300)
}
```

### E218 — Rule 218 (rule-90 pattern on a filtered row)

- **Look:** a single cell grows the same Sierpinski triangle as rule 90 (identical for 200 steps in simulation).
- **Start:** `.centerCell`. **Local rule:** table `11011010`; algebraic form `p + r + pqr`.
- **Variants:** 164 (black/white swap), 164 (mirror + swap).

```swift
.init(id: "E218", title: "Rule 218", behavior: .nesting) {
    SpaceTime(ElementaryCA(rule: 218, width: 401, start: .centerCell), height: 200)
}
```


**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | nesting | Identical to the rule 90 triangle (verified over 200 steps). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `10` → uniform white after 1 step; `110` → static pattern `110` repeating every 3 cells; `100` → static pattern `011` repeating every 3 cells after 1 step; `1100` → uniform black after 1 step. |
| R random | **class 2** | Class 2 (ch6 p.225): a random row freezes in ≈ 4–6 steps into black (≈ 92 %) with static isolated white cells `[sim]`. The chapter's note adds that adjacent pairs of black cells flood their surroundings with black, while rows with no such pairs follow the rule 90 nested evolution. |

**Atlas rule properties.** Equivalents — mirror: itself, black/white swap: 164, mirror + swap: 164. Algebraic form (mod 2, p = left, q = center, r = right): `p + r + pqr`.

```swift
.init(id: "E218.P", title: "Rule 218, block 110", behavior: .nesting,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(ElementaryCA(rule: 218, width: 399, initial: .block([1, 1, 0])), height: 200)
},
.init(id: "E218.R", title: "Rule 218, random start", behavior: .nesting,
      start: .random, wolframClass: .class2) {
    SpaceTime(ElementaryCA(rule: 218, width: 400, initial: .random(seed: 218)), height: 300)
}
```

### E94 — Rule 94 (checkerboard triangle with black edges)

- **Look:** a triangle grows at one cell per step with black edges two cells wide and a fine checkerboard interior.
- **Start:** `.centerCell`. **Local rule:** table `01011110`; algebraic form `p + q + r + pq + qr + pqr`.
- **Variants:** 133 (black/white swap), 133 (mirror + swap).

```swift
.init(id: "E94", title: "Rule 94", behavior: .repetition) {
    SpaceTime(ElementaryCA(rule: 94, width: 401, start: .centerCell), height: 200)
}
```


**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | repetition | Checkerboard triangle with 2-cell black edges (see **Look**). The chapter's note states that suitable special seeds make this class 2 rule yield both nested and random patterns (the example picture sits in the book). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `10` → static pattern `10` repeating every 2 cells; `110` → static pattern `110` repeating every 3 cells; `100` → uniform white after 2 steps; `1100` → uniform white after 2 steps. |
| R random | **class 2** | Class 2 (ch6 note and grid, p.232): ≈ 9 % of cells change per step, black ≈ 57 %, small rings settle with periods near 8 `[sim]`; a change stays ≈ 4 cells wide. |

**Atlas rule properties.** Equivalents — mirror: itself, black/white swap: 133, mirror + swap: 133. Algebraic form (mod 2, p = left, q = center, r = right): `p + q + r + pq + qr + pqr`.

```swift
.init(id: "E94.P", title: "Rule 94, block 110", behavior: .repetition,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(ElementaryCA(rule: 94, width: 399, initial: .block([1, 1, 0])), height: 200)
},
.init(id: "E94.R", title: "Rule 94, random start", behavior: .repetition,
      start: .random, wolframClass: .class2) {
    SpaceTime(ElementaryCA(rule: 94, width: 400, initial: .random(seed: 94)), height: 300)
}
```

### E184 — Rule 184 (traffic flow)

- **Look:** a single cell moves right at one cell per step forever.
- **Start:** `.centerCell`. **Local rule:** table `10111000`; algebraic form `p + pq + qr`.
- **Variants:** 226 (mirror), 226 (black/white swap).

```swift
.init(id: "E184", title: "Rule 184", behavior: .repetition) {
    SpaceTime(ElementaryCA(rule: 184, width: 401, start: .centerCell), height: 200)
}
```


**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | repetition | One cell drifting right at full speed (see **Look**). Seeds generated by a substitution system (ch6 p.272 `[ch6]`) give a nested picture because rule 184 can emulate itself on blocks. |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `10` → periodic: pattern repeats every 2 cells, time period 2; `110` → periodic: pattern repeats every 3 cells, time period 3; `100` → periodic: pattern repeats every 3 cells, time period 3; `1100` → periodic: pattern repeats every 2 cells, time period 2 after 1 step. |
| R random | **class 2** | Class 2: the black density is conserved (here 0.51 black) and the whole pattern drifts right (≈ 98 % of cells change per step, rings of 64 settle with period 2 or 64 `[sim]`). A changed cell becomes a single-cell defect traveling right at speed 1. With equal black and white densities the evolution shows nested structure (ch6 p.272). |

**Atlas rule properties.** Equivalents — mirror: 226, black/white swap: 226, mirror + swap: itself. Algebraic form (mod 2, p = left, q = center, r = right): `p + pq + qr`.

```swift
.init(id: "E184.P", title: "Rule 184, block 110", behavior: .repetition,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(ElementaryCA(rule: 184, width: 399, initial: .block([1, 1, 0])), height: 200)
},
.init(id: "E184.R", title: "Rule 184, random start", behavior: .repetition,
      start: .random, wolframClass: .class2) {
    SpaceTime(ElementaryCA(rule: 184, width: 400, initial: .random(seed: 184)), height: 300)
}
```

### E50 — Rule 50 (checkerboard triangle)

- **Look:** a triangle of fine checkerboard, one cell wider on each side per step.
- **Start:** `.centerCell`. **Local rule:** table `00110010`; algebraic form `p + r + pq + pr + qr + pqr`.
- **Variants:** 179 (black/white swap), 179 (mirror + swap).

```swift
.init(id: "E50", title: "Rule 50", behavior: .repetition) {
    SpaceTime(ElementaryCA(rule: 50, width: 401, start: .centerCell), height: 200)
}
```


**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | repetition | Checkerboard triangle (see **Look**). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `10` → periodic: pattern repeats every 2 cells, time period 2; `110` → periodic: pattern repeats every 3 cells, time period 2; `100` → periodic: pattern repeats every 3 cells, time period 2; `1100` → periodic: pattern repeats every 4 cells, time period 2. |
| R random | **class 2** | Class 2 (ch6 grid, p.232): every cell flips every step, so the picture is a checkerboard of two phases separated by frozen defect lines (period 2, 100 % activity `[sim]`); a change stays 1–2 cells wide. |

**Atlas rule properties.** Equivalents — mirror: itself, black/white swap: 179, mirror + swap: 179. Algebraic form (mod 2, p = left, q = center, r = right): `p + r + pq + pr + qr + pqr`.

```swift
.init(id: "E50.P", title: "Rule 50, block 1100", behavior: .repetition,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(ElementaryCA(rule: 50, width: 400, initial: .block([1, 1, 0, 0])), height: 200)
},
.init(id: "E50.R", title: "Rule 50, random start", behavior: .repetition,
      start: .random, wolframClass: .class2) {
    SpaceTime(ElementaryCA(rule: 50, width: 400, initial: .random(seed: 50)), height: 300)
}
```

### E178 — Rule 178 (checkerboard triangle)

- **Look:** a triangle of fine checkerboard, one cell wider on each side per step.
- **Start:** `.centerCell`. **Local rule:** table `10110010`; algebraic form `p + r + pq + pr + qr`.
- **Variants:** none.

```swift
.init(id: "E178", title: "Rule 178", behavior: .repetition) {
    SpaceTime(ElementaryCA(rule: 178, width: 401, start: .centerCell), height: 200)
}
```


**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | repetition | Checkerboard triangle, identical to E50 for 200 steps (verified). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `10` → periodic: pattern repeats every 2 cells, time period 2; `110` → periodic: pattern repeats every 3 cells, time period 2; `100` → periodic: pattern repeats every 3 cells, time period 2; `1100` → periodic: pattern repeats every 4 cells, time period 2. |
| R random | **class 2** | Class 2 (ch6 grid, p.232): the flipping checkerboard of rule 50 with its own set of defect lines (period 2, 100 % activity `[sim]`); a change stays 1–2 cells wide. |

**Atlas rule properties.** Equivalents — mirror: itself, black/white swap: itself, mirror + swap: itself. Algebraic form (mod 2, p = left, q = center, r = right): `p + r + pq + pr + qr`.

```swift
.init(id: "E178.P", title: "Rule 178, block 1100", behavior: .repetition,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(ElementaryCA(rule: 178, width: 400, initial: .block([1, 1, 0, 0])), height: 200)
},
.init(id: "E178.R", title: "Rule 178, random start", behavior: .repetition,
      start: .random, wolframClass: .class2) {
    SpaceTime(ElementaryCA(rule: 178, width: 400, initial: .random(seed: 178)), height: 300)
}
```

### E18 — Rule 18 (rule-90 triangle, random elsewhere)

- **Look:** a single cell grows the same Sierpinski triangle as rule 90 (identical for 200 steps in simulation).
- **Start:** `.centerCell`. **Local rule:** table `00010010`; algebraic form `p + r + pq + qr`.
- **Variants:** 183 (black/white swap), 183 (mirror + swap).

```swift
.init(id: "E18", title: "Rule 18", behavior: .nesting) {
    SpaceTime(ElementaryCA(rule: 18, width: 401, start: .centerCell), height: 200)
}
```


**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | nesting | Identical to the rule 90 triangle (verified over 200 steps). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `10` → uniform white after 1 step; `110` → uniform white after 1 step; `100` → uniform white after 2 steps; `1100` → periodic: pattern repeats every 4 cells, time period 2. |
| R random | **class 3** | Class 3 (ch6 grid, p.232): random with white triangles of all sizes, and black density ≈ 0.25 `[sim]`. A changed cell spreads both ways at nearly full speed (±390 after 400 steps `[sim]`). A low initial density is forgotten (0.05 → 0.25 by step 512 `[sim]`), so the rule generates its randomness. |

**Atlas rule properties.** Equivalents — mirror: itself, black/white swap: 183, mirror + swap: 183. Algebraic form (mod 2, p = left, q = center, r = right): `p + r + pq + qr`.

```swift
.init(id: "E18.P", title: "Rule 18, block 1100", behavior: .nesting,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(ElementaryCA(rule: 18, width: 400, initial: .block([1, 1, 0, 0])), height: 200)
},
.init(id: "E18.R", title: "Rule 18, random start", behavior: .nesting,
      start: .random, wolframClass: .class3) {
    SpaceTime(ElementaryCA(rule: 18, width: 400, initial: .random(seed: 18)), height: 300)
}
```

### E146 — Rule 146 (rule-90 triangle, random elsewhere)

- **Look:** a single cell grows the same Sierpinski triangle as rule 90 (identical for 200 steps in simulation).
- **Start:** `.centerCell`. **Local rule:** table `10010010`; algebraic form `p + r + pq + qr + pqr`.
- **Variants:** 182 (black/white swap), 182 (mirror + swap).

```swift
.init(id: "E146", title: "Rule 146", behavior: .nesting) {
    SpaceTime(ElementaryCA(rule: 146, width: 401, start: .centerCell), height: 200)
}
```


**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | nesting | Identical to the rule 90 triangle (verified over 200 steps). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `10` → uniform white after 1 step; `110` → uniform white after 1 step; `100` → uniform white after 2 steps; `1100` → periodic: pattern repeats every 4 cells, time period 2. |
| R random | **class 3** | Class 3 (ch6 grid, p.232): random with triangles, black density ≈ 0.25 `[sim]`, full-speed spreading of changes (±390 after 400 steps). The initial density is forgotten (0.05 → 0.25 by step 512). |

**Atlas rule properties.** Equivalents — mirror: itself, black/white swap: 182, mirror + swap: 182. Algebraic form (mod 2, p = left, q = center, r = right): `p + r + pq + qr + pqr`.

```swift
.init(id: "E146.P", title: "Rule 146, block 1100", behavior: .nesting,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(ElementaryCA(rule: 146, width: 400, initial: .block([1, 1, 0, 0])), height: 200)
},
.init(id: "E146.R", title: "Rule 146, random start", behavior: .nesting,
      start: .random, wolframClass: .class3) {
    SpaceTime(ElementaryCA(rule: 146, width: 400, initial: .random(seed: 146)), height: 300)
}
```

### E122 — Rule 122 (checkerboard triangle)

- **Look:** a triangle of fine checkerboard, one cell wider on each side per step.
- **Start:** `.centerCell`. **Local rule:** table `01111010`; algebraic form `p + r + pr + pqr`.
- **Variants:** 161 (black/white swap), 161 (mirror + swap).

```swift
.init(id: "E122", title: "Rule 122", behavior: .repetition) {
    SpaceTime(ElementaryCA(rule: 122, width: 401, start: .centerCell), height: 200)
}
```


**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | repetition | Checkerboard triangle, identical to E50 for 200 steps (verified). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `10` → periodic: pattern repeats every 2 cells, time period 2; `110` → uniform white after 2 steps; `100` → uniform white after 3 steps; `1100` → uniform white after 2 steps. |
| R random | **class 3** | Class 3 (ch6 grid, p.232): random with density ½ and large white triangles; changes spread both ways at nearly full speed (±390 after 400 steps `[sim]`); the initial density is forgotten (0.05 → 0.50 by step 256). |

**Atlas rule properties.** Equivalents — mirror: itself, black/white swap: 161, mirror + swap: 161. Algebraic form (mod 2, p = left, q = center, r = right): `p + r + pr + pqr`.

```swift
.init(id: "E122.P", title: "Rule 122, block 10", behavior: .repetition,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(ElementaryCA(rule: 122, width: 400, initial: .block([1, 0])), height: 200)
},
.init(id: "E122.R", title: "Rule 122, random start", behavior: .repetition,
      start: .random, wolframClass: .class3) {
    SpaceTime(ElementaryCA(rule: 122, width: 400, initial: .random(seed: 122)), height: 300)
}
```

### E126 — Rule 126 (black Sierpinski, doubled blocks)

- **Look:** a single cell grows a black Sierpinski-like triangle on white whose cells come in pairs (the black/white swap of E129).
- **Start:** `.centerCell`. **Local rule:** table `01111110`; algebraic form `p + q + r + pq + pr + qr`.
- **Variants:** 129 (black/white swap), 129 (mirror + swap).

```swift
.init(id: "E126", title: "Rule 126", behavior: .nesting) {
    SpaceTime(ElementaryCA(rule: 126, width: 401, start: .centerCell), height: 200)
}
```


**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | nesting | Black nested triangle on white (the swap of E129). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `10` → uniform white after 2 steps; `110` → uniform white after 2 steps; `100` → uniform white after 2 steps; `1100` → uniform white after 2 steps. |
| R random | **class 3** | The rule the chapter uses as its class 3 example (ch6 p.226, p.250–251, p.267–269): random with black density ½, white triangles of all sizes, and a change spreading both ways at full speed. A low initial density is forgotten. Special rows built from 2-cell blocks (`00`, `11`) make it follow rule 90 on every other step, and a special mixture of two other blocks gives simple class 2 behavior (ch6 p.267, the block symbols are lost in the PDF text layer). |

**Atlas rule properties.** Equivalents — mirror: itself, black/white swap: 129, mirror + swap: 129. Algebraic form (mod 2, p = left, q = center, r = right): `p + q + r + pq + pr + qr`.

```swift
.init(id: "E126.P", title: "Rule 126, block 10", behavior: .nesting,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(ElementaryCA(rule: 126, width: 400, initial: .block([1, 0])), height: 200)
},
.init(id: "E126.R", title: "Rule 126, random start", behavior: .nesting,
      start: .random, wolframClass: .class3) {
    SpaceTime(ElementaryCA(rule: 126, width: 400, initial: .random(seed: 126)), height: 300)
}
```

### E182 — Rule 182 (black-dominated random)

- **Look:** a single cell grows a black-dominated nested triangle: black with white holes at every scale (density ≈ 0.7 after 300 steps).
- **Start:** `.centerCell`. **Local rule:** table `10110110`; algebraic form `p + q + r + pr + pqr`.
- **Variants:** 146 (black/white swap), 146 (mirror + swap).

```swift
.init(id: "E182", title: "Rule 182", behavior: .nesting) {
    SpaceTime(ElementaryCA(rule: 182, width: 401, start: .centerCell), height: 200)
}
```


**Initial conditions** (S one cell, P repeating block, R random with each cell independent)

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | nesting | Black triangle with nested white holes (see **Look**). |
| P repetitive | periodic (period ≤ 2ⁿ for an n-cell block) | `10` → uniform black after 1 step; `110` → uniform black after 2 steps; `100` → uniform black after 1 step; `1100` → periodic: pattern repeats every 4 cells, time period 2. |
| R random | **class 3** | Class 3 (ch6 p.227): random with black density **¾** (ch6 note; measured 0.746) where each white cell tends to be surrounded by black. A change spreads both ways at nearly full speed (±385 after 400 steps `[sim]`). The initial density is forgotten (0.05 → 0.75). |

**Atlas rule properties.** Equivalents — mirror: itself, black/white swap: 146, mirror + swap: 146. Algebraic form (mod 2, p = left, q = center, r = right): `p + q + r + pr + pqr`.

```swift
.init(id: "E182.P", title: "Rule 182, block 1100", behavior: .nesting,
      start: .repetitive, wolframClass: nil) {
    SpaceTime(ElementaryCA(rule: 182, width: 400, initial: .block([1, 1, 0, 0])), height: 200)
},
.init(id: "E182.R", title: "Rule 182, random start", behavior: .nesting,
      start: .random, wolframClass: .class3) {
    SpaceTime(ElementaryCA(rule: 182, width: 400, initial: .random(seed: 182)), height: 300)
}
```

### 7.3 Totalistic with 2 colors and next-nearest neighbors (code 20)

The chapter's first class 4 example (ch6 p.281). The new color depends on the sum of five cells `l2 + l1 + c + r1 + r2` (0…5), so the table has 6 entries and the rule space holds 64 codes (32 that keep white). Code 20 is `010100` in binary: sum 2 → 1, sum 4 → 1, all other sums → 0.

```swift
public struct RadiusTotalisticCA: RowProgram {
    public let width: Int
    public let colors: Int
    public let radius: Int
    public let code: Int
    private let table: [UInt8]          // (2r+1)(k-1)+1 entries
    private var cells: [UInt8]
    private var scratch: [UInt8]

    public init(code: Int, colors: Int = 2, radius: Int = 2, width: Int, initial: InitialCondition) {
        self.code = code; self.colors = colors; self.radius = radius; self.width = width
        var t = [UInt8](); var rest = code
        for _ in 0..<((2 * radius + 1) * (colors - 1) + 1) {
            t.append(UInt8(rest % colors)); rest /= colors
        }
        table = t
        let row = initial.row(width: width, colors: colors)
        cells = row; scratch = row
    }

    public mutating func step() {
        for i in 0..<width {
            var s = 0
            for d in -radius...radius { s += Int(cells[(i + d + width) % width]) }
            scratch[i] = table[s]
        }
        swap(&cells, &scratch)
    }

    public func row() -> [UInt8] { cells }
}
```

### K2R2-20 — 2-color totalistic code 20, radius 2

- **Look:** most small seeds die out. Seeds that survive leave persistent structures on a white background: stationary ones, ones that drift, and a period-22 oscillator.
- **Start:** `.number(n)` seeds, `.random(seed:)` rows.

**Initial conditions**

| Start | Class / type | Effect |
| --- | --- | --- |
| S simple | persistent structures from special seeds | A single cell dies. Seeds 1, 3, 5, 7 and 15 die out `[sim]`. Seed 187 leaves a structure of width 12 that moves one cell every 9 steps. Seed 189 leaves a fixed structure of width 8. Seeds 195 and 219 both leave the same period-22 oscillator of width 28 (ch6 p.281–283 `[ch6]`, reproduced `[sim]`). The chapter catalogs further structures with periods up to 15 among the first twenty-five billion seeds. |
| P repetitive | periodic | A repeated block evolves like a ring of its own size (period ≤ 2ⁿ). |
| R random | **class 4** (ch6 p.281) | A random row thins out to a sparse set of persistent structures on white: black density 1.6 %, 1.5 % of cells change per step after 1500 steps `[sim]`. |

```swift
.init(id: "K2R2-20", title: "2-color totalistic 20, radius 2", behavior: .complexity,
      start: .random, wolframClass: .class4) {
    SpaceTime(RadiusTotalisticCA(code: 20, colors: 2, radius: 2, width: 600, initial: .random(seed: 20)), height: 400)
},
.init(id: "K2R2-20.S195", title: "code 20, seed 195", behavior: .complexity,
      start: .simple, wolframClass: .class4) {
    SpaceTime(RadiusTotalisticCA(code: 20, colors: 2, radius: 2, width: 301, initial: .number(195)), height: 120)
}
```
