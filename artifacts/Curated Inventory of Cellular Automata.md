# Curated Inventory of Cellular Automata

---

## 1. Basic algorithms

### 1.1 Elementary cellular automaton (E entries)

1. Keep a row of cells, each white (0) or black (1), on a ring so the right neighbor of the last cell is the first cell.
2. For each cell, read its left neighbor, itself and its right neighbor as a 3-digit binary number from 0 (white-white-white) to 7 (black-black-black).
3. Write the rule number in binary with 8 digits. Digit number n, counted from the right starting at 0, is the new color for neighborhood n.
4. Compute all new cells from the old row, then replace the row. Each row is one step and rows stack downward to form the picture.
5. For a single-cell start, make the row at least 2 × steps + 1 cells wide so the pattern never reaches the wrap-around edge. Place the black cell in the center, or at the right edge for rule 110.

### 1.2 Totalistic cellular automaton with 3 colors (T entries)

1. Keep a row of cells with colors white (0), gray (1) and black (2) on a ring.
2. For each cell, add the values of its left neighbor, itself and its right neighbor. The sum runs from 0 to 6.
3. Write the code in base 3 with 7 digits. Digit s, counted from the right starting at 0, is the new color for sum s. For example, code 777 is 1001210 in base 3, so sum 0 gives white, 1 gives gray, 2 gives black, 3 gives gray, and sums 4 and 5 give white and 6 gives gray.
4. Compute all new cells from the old row, then replace the row.
5. Start from a single gray cell in the center. Codes divisible by 3 map sum 0 to white, which keeps an empty row empty.
6. Draw white, gray and black as three shades.

### 1.3 Totalistic cellular automaton with next-nearest neighbors (K2R2 entries)

1. Keep a row of white (0) and black (1) cells on a ring.
2. For each cell, add the values of the two cells on each side and the cell itself. The sum runs from 0 to 5.
3. Write the code in binary with 6 digits. Digit s from the right is the new color for sum s. Code 20 is 010100, so sums 2 and 4 give black and all other sums give white.
4. Compute all new cells from the old row, then replace the row.

### 1.4 Starting rows for the special entries

- **Seed number n:** write n in binary (base 3 for 3-color rules), most significant digit first, on a white row beginning at the center cell.
- **Random row:** choose each cell independently. For 2 colors a cell is black with the stated probability, one half unless the entry says otherwise.
- **Repeated block:** copy the block across the whole row, using a width that is a multiple of the block length.
- **Evidence tags:** `[ch6]` marks a chapter statement (page given) and `[sim]` a value measured by simulation. An ID such as `E90.rand` names a rule together with a special starting row; entries without a suffix start from a single cell.
- **Random 2-cell blocks:** fill the row with blocks chosen at random between white-white and black-black.

### 1.5 Recognizing the four types

Run the single-cell start for a few hundred steps and look at the picture. A pattern that repeats in space and time is **repetition**. A pattern made of triangles at every scale is **nesting**. A pattern with no visible regularity beyond its edges is **randomness**. A pattern with localized structures that move and collide is **complex**.

---

## 2. Simple repetition

### E250 — Rule 250 (checkerboard triangle)

- **Look:** a single cell widens into a triangle at one cell per step. The interior fills with a fine checkerboard that flips every step, bounded by two sharp diagonals.
- **Start:** a single black cell in the center. **Rule:** a cell turns black when its left or right neighbor is black.
- **Variants:** 160.

### E109 — Rule 109 (striped field, repeating triangles)

- **Look:** the empty background alternates black and white every step, which draws horizontal stripes across the whole screen. Inside, a growing triangle holds a lattice of small interlocking triangle motifs that repeat in a fixed pattern.
- **Start:** a single black cell in the center. **Rule:** the outcome is white for black-black-black, black-white-white and white-white-black, and black for the other five neighborhoods, so an empty background turns black.
- **Variants:** 73 is its black/white swap.

### E190 — Rule 190 (black triangle with diagonal stripes)

- **Look:** a solid black triangle expands at full speed, crossed by evenly spaced diagonal white stripes that run parallel to one edge.
- **Start:** a single black cell in the center. **Rule:** a cell turns black in every neighborhood except all-white and black-black-white.

### T600 — 3-color totalistic 600 (fixed-width column of triangles)

- **Look:** a single gray cell grows into a narrow column of stacked, textured triangles. The width stays constant while the same bands recur down the screen.
- **Start:** single gray cell. **Variants (same behavior class in the chapter):** 843, 1086.

### T1329 — 3-color totalistic 1329 (period 78)

- **Look:** a column of fixed width with large gray-and-black triangular bands. The whole pattern repeats exactly every 78 steps, the longest period among the fixed-size 3-color totalistic rules in the chapter.
- **Start:** single gray cell. **Check:** after a short transient, the trimmed row at step *t* equals the trimmed row at *t − 78* (confirmed by simulation: first repeat at t = 110 matching t = 32).

### T219 — 3-color totalistic 219 (vertical-striped triangle)

- **Look:** a triangle grows at full speed. A regular comb of thin vertical lines fills its interior, spaced evenly and unchanging.
- **Start:** single gray cell.

### T957 — 3-color totalistic 957 (fine lattice triangle)

- **Look:** a clean triangle filled edge to edge with a tiny, regular lattice texture, like woven cloth.
- **Start:** single gray cell.

### T966 — 3-color totalistic 966 (striped core)

- **Look:** a triangle whose edges carry a fine lattice while the middle shows dense horizontal banding split by a vertical seam.
- **Start:** single gray cell.

### T1884 — 3-color totalistic 1884 (dark scale pattern)

- **Look:** a dark-textured triangle filled with a regular arched, scale-like lattice in black and gray.
- **Start:** single gray cell.

### E30.block1100 — Rule 30 from the block 1100

- **Look:** the four-cell block black-black-white-white repeated across the board gives a pattern of period 8, one of the few repetitive pictures rule 30 can produce `[ch6 p.268]`.
- **Start:** the block 1100 repeated over a row whose width is a multiple of 4. Other repeating blocks give period 1 (1 cell and 2 cells), 3 (12 cells), 4 (7), 5 (5), 6 (84), 7 (15), 9 (15) and 10 (155); no block gives period 2 `[ch6 p.268]`.
- **Checks:** period 8 with a spatial period of 4 cells `[sim]`.

### T1329.seed916 — Code 1329 from seed 916

- **Look:** the first seed of code 1329 that produces a moving structure: a compact object of 17–30 cells that travels across the white background `[ch6 p.287]`.
- **Start:** seed number 916 in base 3.
- **Checks:** width 22 / 24 / 30 at steps 500 / 1000 / 2000 `[sim]`.

### K2R2-20.seed195 — Code 20 from seed 195

- **Look:** from the cells black-black-white-white-white-white-black-black a period-22 oscillator forms on the white background, 28 cells wide `[ch6 p.281–283]`. Seed 219 leaves the same oscillator. Seed 189 leaves a fixed 8-cell structure and seed 187 a structure that moves one cell every 9 steps. Single cells and seeds 3, 5, 7 and 15 die out.
- **Start:** seed number 195 (binary 11000011).
- **Checks:** period 22 and width 28 for seeds 195 and 219; period 9 with a shift of one cell for seed 187 `[sim]`.

---

## 3. Nesting (fractal)

### E90 — Rule 90 (Sierpinski triangle)

- **Look:** a single cell grows into the Sierpinski triangle: white triangular holes at every scale inside a black lace, symmetric left to right. Fractal dimension log₂3 ≈ 1.58.
- **Start:** a single black cell in the center. **Rule:** a cell turns black when exactly one of its two neighbors is black; the center cell is ignored.
- **Variants:** 165.

### E22 — Rule 22

- **Look:** a symmetric nested triangle in the same family as rule 90, with slightly different detail inside the holes. Fractal dimension log₂3.
- **Start:** a single black cell in the center. **Rule:** a cell turns black when exactly one of the three cells in its neighborhood is black.
- **Variants:** 151.

### E60 — Rule 60 (one-sided Sierpinski)

- **Look:** a right-angled Sierpinski triangle that grows to one side, with a vertical edge on one side and a diagonal on the other.
- **Start:** a single black cell in the center. **Rule:** a cell turns black when it and its left neighbor have different colors.
- **Variants:** 102 (mirror), 153, 195.

### E150 — Rule 150 (dense nested lattice)

- **Look:** a symmetric triangle with a busier nested structure: small branching tree-like clusters inside larger triangular voids. Fractal dimension log₂(1 + √5) ≈ 1.69.
- **Start:** a single black cell in the center. **Rule:** a cell turns black when an odd number of the three cells in its neighborhood are black.

### E105 — Rule 105 (nested pattern on a striped field)

- **Look:** the nested structure of rule 150 in inverted form. The background alternates black and white each step, drawing horizontal stripes, and the fractal triangle sits within it.
- **Start:** a single black cell in the center. **Rule:** a cell turns black when an even number of the three cells in its neighborhood are black.

### E129 — Rule 129 (white Sierpinski on black)

- **Look:** a solid black screen with an inverted Sierpinski triangle in white whose holes show black at every scale.
- **Start:** a single black cell in the center. **Rule:** a cell turns black when all three cells in its neighborhood have the same color. The empty background turns black after the first step and stays black.
- **Variants:** 126 (black Sierpinski on white): a cell turns black when at least one but not all of its three cells are black.

### E225 — Rule 225 (narrow nested band)

- **Look:** a nested pattern confined to a diagonal band. Its width grows only like the square root of the number of steps, so the picture is a thin fractal ribbon sliding across a black field.
- **Start:** a single black cell in the center. **Rule:** the opposite of rule 30's outcome in every neighborhood.
- **Variants:** 106, 120, 169.

### T237 — 3-color totalistic 237

- **Look:** a Sierpinski-like triangle with large white holes and fine gray detail, the most common nested form among the 3-color rules (the chapter groups 237 and 948 as the two most common).
- **Start:** single gray cell.

### T948 — 3-color totalistic 948

- **Look:** nested triangles whose interiors branch into small tree-shaped motifs, giving a leafier fractal than T237.
- **Start:** single gray cell.

### T1749 — 3-color totalistic 1749

- **Look:** nested triangles with solid black triangular voids at several scales, which gives the pattern more weight and contrast than the Sierpinski forms.
- **Start:** single gray cell.

### T420 — 3-color totalistic 420

- **Look:** a sparser nested triangle with large clean white regions and a branching rhythm that differs from the 2-color forms (the one structure the chapter calls new among nested 3-color rules).
- **Start:** single gray cell.

### E90.sparse — Rule 90 from a sparse random row

- **Look:** sparse speckle (black density 0.05) that rebuilds itself at steps 2ⁿ. The row at step 2ⁿ is two shifted copies of the initial row, so its density returns to about 0.1 (measured 0.097 at steps 256 and 512) and fills in to about 0.5 in between (0.496 at step 1000). Bands of thin speckle repeat at doubling intervals `[ch6 p.265]`.
- **Start:** a random row in which each cell is black with probability 0.05, about 1000 cells wide.
- **Checks:** rule 150 follows the same rhythm at about 0.14 and rule 60 at about 0.10 `[sim]`.

### E126.pairs — Rule 126 from 2-cell blocks

- **Look:** a nested pattern that is rule 90's with each cell doubled. Rows are made of randomly chosen white-white and black-black blocks, and rule 126 acts on the blocks exactly like rule 90 acts on single cells: after every second step the block colors equal the rule 90 row `[ch6 p.269]`.
- **Start:** a row of random 2-cell blocks, each entirely white or entirely black.
- **Checks:** block colors match rule 90 at steps 2, 4, …, 40 with no shift `[sim]`. This is also why E129 and its swap 126 give the Sierpinski pattern from a single cell.

### E184.rand — Rule 184 from a random row

- **Look:** traffic flow: black cells drift right until blocked, the black density stays at its initial value (0.509 measured), and with equal black and white densities nested structure shows in the evolution `[ch6 p.272]`.
- **Start:** a random row, density one half.
- **Checks:** 98 % of cells change per step; a one-cell change travels right at speed 1 as a single-cell defect `[sim]`.

---

## 4. Randomness

### E30 — Rule 30

- **Look:** the left edge is a clean diagonal line. The rest is a disordered tangle of black and white with scattered white triangles of every size. The center column is statistically random (Wolfram's random number generator).
- **Start:** a single black cell in the center. **Rule:** a cell turns black when its left neighbor differs in color from the answer to "is the center or right cell black?".
- **Variants:** 86, 135 (black background), 149 (black background).

### E45 — Rule 45

- **Look:** a regular diagonal on one side and a mix of short vertical dashes and irregular blocks filling the rest, with fewer triangular voids than rule 30. Horizontal stripes cover the background.
- **Start:** a single black cell in the center. **Rule:** a cell turns black when its left neighbor differs in color from the answer to "is the center cell black or the right cell white?".
- **Variants:** 75, 89, 101.

### E73 — Rule 73

- **Look:** a symmetric triangle of fine, dotted, speckled texture with no long diagonals, giving a smoother grain than rules 30 and 45. Horizontal stripes cover the background.
- **Start:** a single black cell in the center. **Rule:** the outcome is black for white-white-white, black-black-white and white-black-black, and white for the other five neighborhoods.
- **Variants:** 109, its black/white swap. From a single black cell on white, rule 109 produces the repetitive picture in E109 while rule 73 produces this one.

### T177 — 3-color totalistic 177

- **Look:** a triangle whose entire interior is a gray-and-black scatter with no regular structure, bounded by clean diagonals.
- **Start:** single gray cell.

### T912 — 3-color totalistic 912

- **Look:** a mostly random interior with a visible grain of small triangles, and a more regular band along the edges.
- **Start:** single gray cell.

### T2040 — 3-color totalistic 2040

- **Look:** random texture broken by dark triangular patches of solid black of various sizes.
- **Start:** single gray cell.

### E90.rand — Rule 90 from a random row

- **Look:** a random-looking field with white triangles of every size and black density one half (measured 0.502). Rule 90 adds shifted copies of the single-cell triangle, so the picture carries the randomness of the initial row `[ch6 p.264]`.
- **Start:** a random row, each cell black or white with equal probability.
- **Variants:** rules 150 and 60 are also additive and give the same kind of picture.
- **Checks:** a one-cell change spreads both ways at full speed, ±400 cells after 400 steps `[sim]`.

### E22.rand — Rule 22 from a random row

- **Look:** a random field with white triangles whose black density settles near 0.35 (measured 0.348; the chapter gives 0.35095). A low initial density (0.05) is forgotten within about 100 steps, so the field comes from the rule itself `[ch6 p.265]`.
- **Start:** a random row, density one half.
- **Checks:** a one-cell change spreads at about 0.77 cells per step on each side (chapter: 0.766).

### E22.seed19 — Rule 22 from seed 19

- **Look:** from five initial cells (`10011`) the pattern grows a random core with black density about 0.35 that widens at about 0.766 cells per step, with repetitive regions on both sides `[ch6 p.263 and note]`. The single-cell pattern of E22 is nested; this seed gives rule-30-like randomness.
- **Start:** seed number 19. Seeds 25, 37, 38, 39, 41, 45, 47, 51, 57 and 61 give the same kind of picture.
- **Checks:** the central block compresses to 0.88 of its size, the value for a density-0.35 random source, while seeds 1–18 compress to 0.002 (nested) `[sim]`.

### E126.rand — Rule 126 from a random row

- **Look:** the chapter's showcase of a rule that never settles: random with black density one half and white triangles at all scales `[ch6 p.226]`.
- **Start:** a random row, about 300 cells wide.
- **Variants:** 129 (black/white swap).
- **Checks:** density 0.517 after 1000 steps; a one-cell change spreads both ways at nearly full speed `[sim]`.

---

## 5. Complex localized structures

### E110 — Rule 110

- **Look:** from a single cell the pattern grows to one side. A regular background of small triangles forms, and localized structures of many sizes travel through it at different speeds and collide in intricate ways. The left part settles into a regular lattice while the active region keeps producing new structures. Rule 110 is computationally universal.
- **Start:** a single black cell at the right edge, with the view pinned to the right so the pattern grows leftward (as in the earlier Rust experiment). **Rule:** a cell turns black when its center or right cell is black, except when all three cells are black.
- **Variants:** 124 (mirror), 137, 193.

### E54 — Rule 54 (random start)

- **Look:** from a single cell the picture is a plain checkerboard triangle. From a random row it develops a regular background crossed by moving localized structures that collide and interact. Chapter 6 of the book studies it; chapter 3 does not show it.
- **Start:** a random row. **Rule:** a cell flips its color when at least one of its two neighbors is black and keeps it otherwise.
- **Variants:** 147.

### T1041 — 3-color totalistic 1041

- **Look:** a growing triangle that fills with a mixture of regular stripes and irregular regions; the chapter reports that the pattern becomes repetitive after about 150 steps.
- **Start:** single gray cell.

### T1635 — 3-color totalistic 1635

- **Look:** black triangular regions of many sizes separated by textured, irregular zones, with localized structures crossing between them. After 3000 steps the chapter finds the long-term outcome still unclear.
- **Start:** single gray cell. Run to 3000 steps.

### T2049 — 3-color totalistic 2049

- **Look:** a large solid black wedge near the center flanked by long vertical lines, with a busy, irregular fringe of small structures along both outer sides. Its long-term outcome is also unclear after 3000 steps.
- **Start:** single gray cell. Run to 3000 steps.

### T1599 — 3-color totalistic 1599 (the long transient)

- **Look:** from one gray cell the pattern grows irregularly for thousands of steps, reaching a width of roughly 670 cells (measured). Growth then slows, regions inside die out, and bursts of growth recur. At step 8282 it resolves into 31 simple repetitive structures.
- **Start:** single gray cell. Run to at least 8300 steps; the live region stays within about 1000 cells.
- **Check:** the live region stays near 670 cells wide through steps 4000–8600 in simulation, and the chapter gives 8282 as the resolution step.

### E110.rand — Rule 110 from a random row

- **Look:** within a few steps the row organizes into a regular background of small triangles crossed by localized structures that move at different speeds and collide; 700 steps fill a page of the book `[ch6 p.229–230]`.
- **Start:** a random row, about 400 cells wide, run for 700 steps.
- **Variants:** 124, 137, 193.
- **Checks:** black density 0.57 after 1000 steps; a one-cell change spreads only when a moving structure carries it, covering 150–240 cells after 400 steps `[sim]`.

### T1329.seed54889 — Code 1329 from seed 54 889

- **Look:** the first seed with unbounded growth: a complex region widens by about half a cell per step on each side for as long as the run lasts `[ch6 p.287–289]`.
- **Start:** seed number 54 889 in base 3. Seeds 97 439, 115 396, 166 426 and 2 069 116 also grow without bound.
- **Checks:** width 205 / 450 / 952 at steps 500 / 1000 / 2000; seed 97 439 gives 261 / 511 / 1011 `[sim]`.

### T357.seed28 — Code 357 from seed 28

- **Look:** code 357 lets most small seeds die out; seed 28 leaves a persistent structure of 8–20 cells `[ch6 p.286]`.
- **Start:** seed number 28 in base 3.
- **Checks:** width 8 / 20 / 14 at steps 100 / 500 / 1500 `[sim]`.

---

## 6. Summary

| Type | Elementary | 3-color totalistic |
| --- | --- | --- |
| Repetition | 250, 109, 190, E30.block1100, K2R2-20.seed195 | 600, 1329, 219, 957, 966, 1884, T1329.seed916 |
| Nesting | 90, 22, 60, 150, 105, 129, 225, E90.sparse, E126.pairs, E184.rand | 237, 948, 1749, 420 |
| Randomness | 30, 45, 73, E90.rand, E22.rand, E22.seed19, E126.rand | 177, 912, 2040 |
| Complex localized structures | 110, 54 (random start), E110.rand | 1041, 1635, 2049, 1599, T1329.seed54889, T357.seed28 |

Total: 45 entries.