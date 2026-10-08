# Curated Inventory of Cellular Automata

Source: Wolfram, *A New Kind of Science*, chapter 3 (elementary rules and 3-color totalistic rules), with rule numbering and totalistic coding checked against the Wolfram Atlas, MathWorld and the Wolfram code definition.

Every entry keeps visible structure over a few hundred steps and carries four things: its **type** (repetition, nesting, randomness, complex localized structures), a short account of **how it looks and evolves**, its **start** condition, and its **algorithm** as a Swift `Program` for the harness (`RowProgram` + `SpaceTime`, see `harness-design.md`).

**IDs.** `E<n>` is elementary rule *n* (2 colors, nearest neighbors). `T<n>` is 3-color totalistic code *n*. **Equivalents.** Mirror images and black/white swaps of a rule give the same picture up to that transform (a swap changes the background). They are listed as *Variants*.

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

### E109 — Rule 109 (striped field, repeating triangles)

- **Look:** the empty background alternates black and white every step, which draws horizontal stripes across the whole screen. Inside, a growing triangle holds a lattice of small interlocking triangle motifs that repeat in a fixed pattern.
- **Start:** `.centerCell`. **Local rule:** table `01101101` (000 → 1, 111 → 0).
- **Variants:** 73 is its black/white swap.

```swift
.init(id: "E109", title: "Rule 109", behavior: .repetition) {
    SpaceTime(ElementaryCA(rule: 109, width: 321, start: .centerCell), height: 160)
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

### T600 — 3-color totalistic 600 (fixed-width column of triangles)

- **Look:** a single gray cell grows into a narrow column of stacked, textured triangles. The width stays constant while the same bands recur down the screen.
- **Start:** single gray cell. **Variants (same behavior class in the chapter):** 843, 1086.

```swift
.init(id: "T600", title: "3-color totalistic 600", behavior: .repetition) {
    SpaceTime(TotalisticCA(code: 600, width: 161), height: 300)
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

### T219 — 3-color totalistic 219 (vertical-striped triangle)

- **Look:** a triangle grows at full speed. A regular comb of thin vertical lines fills its interior, spaced evenly and unchanging.
- **Start:** single gray cell.

```swift
.init(id: "T219", title: "3-color totalistic 219", behavior: .repetition) {
    SpaceTime(TotalisticCA(code: 219, width: 321), height: 160)
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

### T966 — 3-color totalistic 966 (striped core)

- **Look:** a triangle whose edges carry a fine lattice while the middle shows dense horizontal banding split by a vertical seam.
- **Start:** single gray cell.

```swift
.init(id: "T966", title: "3-color totalistic 966", behavior: .repetition) {
    SpaceTime(TotalisticCA(code: 966, width: 321), height: 160)
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

### E22 — Rule 22

- **Look:** a symmetric nested triangle in the same family as rule 90, with slightly different detail inside the holes. Fractal dimension log₂3.
- **Start:** `.centerCell`. **Local rule:** `(l + c + r) == 1 ? 1 : 0`.
- **Variants:** 151.

```swift
.init(id: "E22", title: "Rule 22", behavior: .nesting) {
    SpaceTime(ElementaryCA(rule: 22, width: 401, start: .centerCell), height: 200)
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

### E150 — Rule 150 (dense nested lattice)

- **Look:** a symmetric triangle with a busier nested structure: small branching tree-like clusters inside larger triangular voids. Fractal dimension log₂(1 + √5) ≈ 1.69.
- **Start:** `.centerCell`. **Local rule:** `l ^ c ^ r`.

```swift
.init(id: "E150", title: "Rule 150", behavior: .nesting) {
    SpaceTime(ElementaryCA(rule: 150, width: 401, start: .centerCell), height: 200)
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

### E129 — Rule 129 (white Sierpinski on black)

- **Look:** a solid black screen with an inverted Sierpinski triangle in white whose holes show black at every scale.
- **Start:** `.centerCell`. **Local rule:** `(l == c && c == r) ? 1 : 0`. The empty background turns black after the first step (000 → 1) and stays black (111 → 1).
- **Variants:** 126 (black Sierpinski on white): `(l | c | r) & ~(l & c & r)`.

```swift
.init(id: "E129", title: "Rule 129", behavior: .nesting) {
    SpaceTime(ElementaryCA(rule: 129, width: 401, start: .centerCell), height: 200)
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

### T237 — 3-color totalistic 237

- **Look:** a Sierpinski-like triangle with large white holes and fine gray detail, the most common nested form among the 3-color rules (the chapter groups 237 and 948 as the two most common).
- **Start:** single gray cell.

```swift
.init(id: "T237", title: "3-color totalistic 237", behavior: .nesting) {
    SpaceTime(TotalisticCA(code: 237, width: 401), height: 200)
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

### T1749 — 3-color totalistic 1749

- **Look:** nested triangles with solid black triangular voids at several scales, which gives the pattern more weight and contrast than the Sierpinski forms.
- **Start:** single gray cell.

```swift
.init(id: "T1749", title: "3-color totalistic 1749", behavior: .nesting) {
    SpaceTime(TotalisticCA(code: 1749, width: 401), height: 200)
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

### E45 — Rule 45

- **Look:** a regular diagonal on one side and a mix of short vertical dashes and irregular blocks filling the rest, with fewer triangular voids than rule 30. Horizontal stripes cover the background.
- **Start:** `.centerCell`. **Local rule:** `l ^ (c | (1 - r))`.
- **Variants:** 75, 89, 101.

```swift
.init(id: "E45", title: "Rule 45", behavior: .randomness) {
    SpaceTime(ElementaryCA(rule: 45, width: 401, start: .centerCell), height: 200)
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

### T177 — 3-color totalistic 177

- **Look:** a triangle whose entire interior is a gray-and-black scatter with no regular structure, bounded by clean diagonals.
- **Start:** single gray cell.

```swift
.init(id: "T177", title: "3-color totalistic 177", behavior: .randomness) {
    SpaceTime(TotalisticCA(code: 177, width: 601), height: 300)
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

### T2040 — 3-color totalistic 2040

- **Look:** random texture broken by dark triangular patches of solid black of various sizes.
- **Start:** single gray cell.

```swift
.init(id: "T2040", title: "3-color totalistic 2040", behavior: .randomness) {
    SpaceTime(TotalisticCA(code: 2040, width: 601), height: 300)
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

### E54 — Rule 54 (random start)

- **Look:** from a single cell the picture is a plain checkerboard triangle. From a random row it develops a regular background crossed by moving localized structures that collide and interact. Chapter 6 of the book studies it; chapter 3 does not show it.
- **Start:** `.random(seed:)`. **Local rule:** `c ^ (l | r)`.
- **Variants:** 147.

```swift
.init(id: "E54", title: "Rule 54, random start", behavior: .complexity) {
    SpaceTime(ElementaryCA(rule: 54, width: 400, start: .random(seed: 54)), height: 300)
}
```

### T1041 — 3-color totalistic 1041

- **Look:** a growing triangle that fills with a mixture of regular stripes and irregular regions; the chapter reports that the pattern becomes repetitive after about 150 steps.
- **Start:** single gray cell.

```swift
.init(id: "T1041", title: "3-color totalistic 1041", behavior: .complexity) {
    SpaceTime(TotalisticCA(code: 1041, width: 801), height: 400)
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

### T2049 — 3-color totalistic 2049

- **Look:** a large solid black wedge near the center flanked by long vertical lines, with a busy, irregular fringe of small structures along both outer sides. Its long-term outcome is also unclear after 3000 steps.
- **Start:** single gray cell. Run to 3000 steps.

```swift
.init(id: "T2049", title: "3-color totalistic 2049", behavior: .complexity) {
    SpaceTime(TotalisticCA(code: 2049, width: 6101), height: 600)
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

---

## 6. Summary

| Type | Elementary | 3-color totalistic |
| --- | --- | --- |
| Repetition | 250, 109, 190 | 600, 1329, 219, 957, 966, 1884 |
| Nesting | 90, 22, 60, 150, 105, 129, 225 | 237, 948, 1749, 420 |
| Randomness | 30, 45, 73 | 177, 912, 2040 |
| Complex localized structures | 110, 54 (random start) | 1041, 1635, 2049, 1599 |

Total: 32 entries.