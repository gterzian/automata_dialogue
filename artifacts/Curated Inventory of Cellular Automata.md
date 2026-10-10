# Curated Inventory of Cellular Automata

Every automaton below belongs to one of four behavior classes. The class names
the kind of pattern the automaton produces.

- **repetition** — simple and regular. The pattern stays fixed, repeats every
  few steps, or settles into a uniform state. Stripes, checkerboards, and even
  bands.
- **nesting** — self-similar. The pattern is built from smaller copies of
  itself, so triangles or shapes appear at many scales.
- **randomness** — no short rule compresses the pattern. It looks disordered,
  though small triangles may still appear.
- **complexity** — order and randomness mix. Small localized structures form,
  move, and interact with each other in complicated ways.

The 45 entries follow in section 2. Each gives the id, its class, and a
one-sentence description of how it looks.

## 1. Basic algorithms

### 1.1 Elementary cellular automaton (E entries)

1. Keep a row of cells, each white (0) or black (1), on a ring so the right
   neighbor of the last cell is the first cell.
2. For each cell, read its left neighbor, itself and its right neighbor as a
   3-digit binary number from 0 (white-white-white) to 7 (black-black-black).
3. Write the rule number in binary with 8 digits. Digit number n, counted from
   the right starting at 0, is the new color for neighborhood n.
4. Compute all new cells from the old row, then replace the row. Each row is
   one step and rows stack downward to form the picture.
5. For a single-cell start, make the row at least 2 × steps + 1 cells wide so
   the pattern never reaches the wrap-around edge. Place the black cell in the
   center, or at the right edge for rule 110.

### 1.2 Totalistic cellular automaton with 3 colors (T entries)

1. Keep a row of cells with colors white (0), gray (1) and black (2) on a ring.
2. For each cell, add the values of its left neighbor, itself and its right
   neighbor. The sum runs from 0 to 6.
3. Write the code in base 3 with 7 digits. Digit s, counted from the right
   starting at 0, is the new color for sum s. For example, code 777 is 1001210
   in base 3, so sum 0 gives white, 1 gives gray, 2 gives black, 3 gives gray,
   and sums 4 and 5 give white and 6 gives gray.
4. Compute all new cells from the old row, then replace the row.
5. Start from a single gray cell in the center. Codes divisible by 3 map sum 0
   to white, which keeps an empty row empty.
6. Draw white, gray and black as three shades.

### 1.3 Totalistic cellular automaton with next-nearest neighbors (K2R2 entries)

1. Keep a row of white (0) and black (1) cells on a ring.
2. For each cell, add the values of the two cells on each side and the cell
   itself. The sum runs from 0 to 5.
3. Write the code in binary with 6 digits. Digit s from the right is the new
   color for sum s. Code 20 is 010100, so sums 2 and 4 give black and all other
   sums give white.
4. Compute all new cells from the old row, then replace the row.

### 1.4 Starting rows

- **Seed number n:** write n in binary (base 3 for 3-color rules), most
  significant digit first, on a white row beginning at the center cell.
- **Random row:** choose each cell independently. For 2 colors a cell is black
  with the stated probability, one half unless the entry says otherwise.
- **Repeated block:** copy the block across the whole row, using a width that
  is a multiple of the block length.
- **Random 2-cell blocks:** fill the row with blocks chosen at random between
  white-white and black-black.
- An id such as `E90.rand` names a rule together with a special starting row;
  entries without a suffix start from a single cell.

## 2. The automata

- **E250** (repetition): A single cell widens into a triangle at one cell per step, its interior a fine checkerboard that flips each step, bounded by two sharp diagonals.
- **E109** (repetition): A growing triangle of repeating interlocking triangle motifs over a background that alternates black and white each step, drawing horizontal stripes.
- **E190** (repetition): A solid black triangle expands at full speed, crossed by evenly spaced diagonal white stripes parallel to one edge.
- **T600** (repetition): A narrow fixed-width column of stacked, textured gray triangles whose bands recur down the screen.
- **T1329** (repetition): A fixed-width column of large gray-and-black triangular bands that repeats exactly every 78 steps.
- **T219** (repetition): A triangle growing at full speed whose interior is filled with a regular comb of thin, evenly spaced vertical lines.
- **T957** (repetition): A clean triangle filled edge to edge with a tiny regular lattice texture, like woven cloth.
- **T966** (repetition): A triangle whose edges carry a fine lattice while the middle shows dense horizontal banding split by a vertical seam.
- **T1884** (repetition): A dark-textured triangle filled with a regular arched, scale-like lattice in black and gray.
- **E30.block1100** (repetition): The block black-black-white-white repeated across the row gives a pattern of period 8 with a spatial period of 4 cells.
- **K2R2-20.seed195** (repetition): From the cells black-black-white-white-white-white-black-black a period-22 oscillator forms, 28 cells wide.
- **T1329.seed916** (repetition): From seed 916 a compact object of 17 to 30 cells travels across the white background.
- **E90** (nesting): The Sierpinski triangle: white triangular holes at every scale inside a black lace, symmetric left to right.
- **E22** (nesting): A symmetric nested triangle in the same family as rule 90, with slightly different detail inside the holes.
- **E60** (nesting): A right-angled Sierpinski triangle growing to one side, with a vertical edge on one side and a diagonal on the other.
- **E150** (nesting): A symmetric triangle with a busy nested structure: small branching tree-like clusters inside larger triangular voids.
- **E105** (nesting): The nested structure of rule 150 inverted, its fractal triangle sitting inside a background that alternates black and white each step.
- **E129** (nesting): A solid black screen with an inverted white Sierpinski triangle whose holes show black at every scale.
- **E225** (nesting): A nested pattern confined to a thin diagonal band that grows like the square root of the steps, sliding across a black field.
- **T237** (nesting): A Sierpinski-like triangle with large white holes and fine gray detail.
- **T948** (nesting): Nested triangles whose interiors branch into small tree-shaped motifs, a leafier fractal than T237.
- **T1749** (nesting): Nested triangles with solid black triangular voids at several scales, giving more weight and contrast than the Sierpinski forms.
- **T420** (nesting): A sparser nested triangle with large clean white regions and a branching rhythm distinct from the 2-color forms.
- **E90.sparse** (nesting): Sparse speckle at density 0.05 rebuilds itself at steps that are powers of two, so bands of thin speckle repeat at doubling intervals.
- **E126.pairs** (nesting): Random black-black and white-white 2-cell blocks evolve under rule 126 like rule 90 on pairs, so the block colors reproduce rule 90 every second step.
- **E184.rand** (nesting): Traffic flow: black cells drift right until blocked, the black density holds at one half, and nested structure appears in the evolution.
- **E30** (randomness): A clean diagonal left edge and a disordered tangle of black and white with scattered white triangles of every size; the center column is statistically random.
- **E45** (randomness): A regular diagonal on one side and a mix of short vertical dashes and irregular blocks filling the rest, over a horizontally striped background.
- **E73** (randomness): A symmetric triangle of fine, dotted, speckled texture with no long diagonals, over a horizontally striped background.
- **T177** (randomness): A triangle whose entire interior is a gray-and-black scatter with no regular structure, bounded by clean diagonals.
- **T912** (randomness): A mostly random interior with a visible grain of small triangles and a more regular band along the edges.
- **T2040** (randomness): Random texture broken by dark triangular patches of solid black of various sizes.
- **E90.rand** (randomness): A random field with white triangles at every size; rule 90 adds shifted copies of its single-cell triangle, so the picture carries the initial row's randomness.
- **E22.rand** (randomness): A random field with white triangles whose black density settles near 0.35, coming from the rule itself.
- **E22.seed19** (randomness): From the five cells 10011 the pattern grows a random core of density 0.35 that widens, with repetitive regions on both sides.
- **E126.rand** (randomness): A rule that never settles: random texture at density one half with white triangles at all scales.
- **E110** (complexity): From a single cell the pattern grows to one side: a regular background of small triangles with localized structures of many sizes traveling through it and colliding.
- **E54** (complexity): From a random row, a regular background crossed by moving localized structures that collide and interact.
- **T1041** (complexity): A growing triangle filling with a mixture of regular stripes and irregular regions.
- **T1635** (complexity): Black triangular regions of many sizes separated by textured, irregular zones, with localized structures crossing between them.
- **T2049** (complexity): A large solid black wedge near the center flanked by long vertical lines, with a busy irregular fringe of small structures along both outer sides.
- **T1599** (complexity): From one gray cell the pattern grows irregularly for thousands of steps, then regions die out and bursts of growth recur before resolving into many simple repetitive structures.
- **E110.rand** (complexity): Within a few steps a random row organizes into a regular background of small triangles crossed by localized structures that move at different speeds and collide.
- **T1329.seed54889** (complexity): From seed 54889 a complex region widens by about half a cell per step on each side without bound.
- **T357.seed28** (complexity): Code 357 lets most small seeds die out; seed 28 leaves a persistent structure of 8 to 20 cells.
