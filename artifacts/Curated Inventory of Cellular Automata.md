# Curated Inventory of Cellular Automata

Every automaton below belongs to one of four behavior classes. The class names
the kind of pattern the entry's own picture shows on screen, so one rule can
appear several times with different starting rows, each entry tagged by what it
looks like from its stated start.

- **repetition** — simple and regular. The pattern stays fixed, repeats every
  few steps, or settles into a uniform state. Stripes, checkerboards, even
  bands, lattices, and single plain shapes. Stripes or lines at even spacing
  belong here.
- **nesting** — self-similar. The pattern is built from smaller copies of
  itself, so triangles or shapes appear at many scales.
- **randomness** — no short rule compresses the pattern. It looks disordered,
  though small triangles may still appear. Simple marks scattered at irregular
  spacing belong here.
- **complexity** — order and randomness mix. Small localized structures form,
  move, and interact with each other in complicated ways, and large regions of
  different texture meet along structured boundaries.

The 111 entries follow in section 2. Each gives the id, its class, and a
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
5. Start from a single black cell in the center. Even codes keep an empty row
   empty.

### 1.4 Starting rows

- **Single cell (no suffix):** one black cell (gray for T entries) in the
  center of a white row.
- **Seed number n:** write n in binary (base 3 for T entries), most
  significant digit first, on a white row beginning at the center cell.
- **Random row (`.rand`):** choose each cell independently. For 2 colors a cell
  is black with probability one half unless the entry says otherwise. For 3
  colors each of white, gray and black has probability one third. Draw a fresh
  random row on every run, so choosing the same entry twice gives a different
  picture.
- **Repeated block:** copy the block across the whole row, using a width that
  is a multiple of the block length so the pattern closes cleanly around the
  ring.
- **Random 2-cell blocks (`.pairs`):** fill the row with blocks chosen at
  random between white-white and black-black.
- **Injected randomness (`.inject`):** on top of any start, after every step
  one cell is overwritten with a pseudo-random value drawn from the entry's
  seed. The draw is deterministic for a given seed; a fresh seed per run makes
  re-choosing the entry differ.
- An id such as `E90.rand` names a rule together with a special starting row;
  entries without a suffix start from a single cell.

## 2. The automata

- **E250** (repetition): A single cell widens into a triangle at one cell per step, its interior a fine checkerboard that flips each step, bounded by two sharp diagonals.
- **E109** (repetition): A growing triangle of repeating interlocking triangle motifs over a background that alternates black and white each step, drawing horizontal stripes.
- **E190** (repetition): A solid black triangle expands at full speed, crossed by evenly spaced diagonal white stripes parallel to one edge.
- **E28** (repetition): A wedge of evenly spaced vertical stripes grows down and to the right from a single cell, with a clean diagonal edge and empty white on the left.
- **E94** (repetition): A clean triangle filled with evenly spaced vertical stripes, edged by two sharp diagonals.
- **E62** (repetition): From a single cell a triangle grows, its interior a fine diagonal weave that repeats every three steps: even striping on the left, a denser fan on the right.
- **E77** (repetition): Horizontal stripes bend into evenly spaced right-angle corners that fan out from the top center.
- **E57** (repetition): A horizontally striped field with a central wedge of fine woven texture widening downward, lighter on its left half and darker on its right.
- **E54** (repetition): A growing triangle filled with a tight regular lattice of tiny triangles, like woven cloth.
- **E73** (repetition): A symmetric triangle of stacked arches with a dotted core grows over a horizontally striped background.
- **T1047** (repetition): A dark triangle filled with thin horizontal stripes, with a ragged light fringe along its edges.
- **T183** (repetition): A triangle of fine black-and-white checker lattice split by one vertical seam down the center.
- **T600** (repetition): A narrow column of stacked, textured gray triangles, 11 to 25 cells wide, whose bands recur down the screen.
- **T1329** (repetition): A narrow column of large gray-and-black triangular bands, 9 to 23 cells wide, whose shape repeats exactly every 78 steps.
- **T219** (repetition): A triangle growing at full speed whose interior is filled with a regular comb of thin, evenly spaced vertical lines.
- **T957** (repetition): A clean triangle filled edge to edge with a tiny regular lattice texture, like woven cloth.
- **T966** (repetition): A triangle whose edges carry a fine lattice while the middle shows dense horizontal banding split by a vertical seam.
- **T1884** (repetition): A dark-textured triangle filled with a regular arched, scale-like lattice in black and gray.
- **E30.block1100** (repetition): The block black-black-white-white repeated across the row weaves a fine diagonal lattice with period 8 in time and 4 cells across.
- **K2R2-20.seed195** (repetition): From the cells black-black-white-white-white-white-black-black a column 8 to 28 cells wide forms, and its shape repeats every 22 steps.
- **T1329.seed916** (repetition): From seed 916 a compact object 16 to 32 cells wide drifts slowly across the white background.
- **T357.seed28** (repetition): From seed 28 a persistent column of stacked triangular structures, between 8 and 28 cells wide, runs on through at least 1500 steps.
- **E184.rand** (repetition): Parallel diagonal stripes of black and white sweep across the picture, with a few wedge-shaped jams that dissolve into the stripes.
- **E178.rand** (repetition): A woven zigzag texture runs down the picture in vertical columns separated by faint seams.
- **E15.rand** (repetition): Smooth wavy ribbons curve diagonally across the picture.
- **E14.rand** (repetition): Thick parallel diagonal stripes lean to the right, with a few broader bands crossing them.
- **T1662** (repetition): A dark field crossed by evenly spaced vertical columns strung with beaded structures.
- **T1587.rand** (repetition): A flat gray field crossed by evenly spaced vertical columns of small beaded structures.
- **T219.rand** (repetition): A sparse white field crossed by straight vertical lines that stay fixed in place.
- **E90** (nesting): The Sierpinski triangle: white triangular holes at every scale inside a black lace, symmetric left to right.
- **E22** (nesting): A symmetric nested triangle in the same family as rule 90, with slightly different detail inside the holes.
- **E60** (nesting): A right-angled Sierpinski triangle growing to one side, with a vertical edge on one side and a diagonal on the other.
- **E150** (nesting): A symmetric triangle with a busy nested structure: small branching tree-like clusters inside larger triangular voids.
- **E105** (nesting): The nested structure of rule 150 inverted, its fractal triangle sitting inside a background that alternates black and white each step.
- **E129** (nesting): A solid black screen with an inverted white Sierpinski triangle whose holes show black at every scale.
- **E225** (nesting): A nested pattern confined to a thin diagonal band that grows like the square root of the steps, sliding across a black field.
- **E18** (nesting): The Sierpinski triangle drawn as sparse isolated dots, airy and light, with white triangular holes at every scale.
- **E126** (nesting): A bold Sierpinski triangle with thick black edges and white triangular holes at every scale.
- **T237** (nesting): A Sierpinski-like triangle with large white holes and fine gray detail.
- **T948** (nesting): Nested triangles whose interiors branch into small tree-shaped motifs, a leafier fractal than T237.
- **T1749** (nesting): Nested triangles with solid black triangular voids at several scales, giving more weight and contrast than the Sierpinski forms.
- **T420** (nesting): A sparser nested triangle with large clean white regions and a branching rhythm distinct from the 2-color forms.
- **T561** (nesting): A black-edged triangle packed with small white triangular holes of many sizes.
- **T399** (nesting): A dense triangle of fine gray-and-black lines with white triangular holes at many sizes.
- **T1182** (nesting): Nested triangles on a mid-gray ground: flat gray holes at several scales framed by fine black texture.
- **T1419** (nesting): Large flat gray triangular holes at several scales set in a black lace.
- **T1848** (nesting): Solid black triangular voids at several scales set in a gray lace with a pale outline.
- **T1932** (nesting): Heavy solid black triangular voids at every scale in a dark lace, the darkest of the Sierpinski-like forms.
- **T885** (nesting): Nested triangles surround a core of tight horizontal stripes that widens toward the bottom.
- **T1284** (nesting): Nested triangles on either side of a central core of vertical stripes.
- **T453** (nesting): Bold black branching clusters nested inside white triangular voids, a stout tree-like fractal.
- **T1509** (nesting): Slender black branching trees nested inside large white triangular voids.
- **T273** (nesting): A pale gray lace of nested triangles with fine vertical spars.
- **T1410** (nesting): A narrow steep triangle filled with dark nested structure.
- **K2R2-2** (nesting): Sparse nested triangles spread wide and shallow, with large flat white wedges between them.
- **K2R2-30** (nesting): Bold black outlines of nested triangles spread wide and shallow.
- **K2R2-42** (nesting): Wide, shallow nested triangles whose edges sprout small branching trees.
- **E30** (randomness): A disordered black-and-white field of static with scattered white triangles of every size.
- **E45** (randomness): Dense black-and-white static with short vertical dashes and irregular blocks.
- **T177** (randomness): A triangle whose entire interior is a gray-and-black scatter with no regular structure, bounded by clean diagonals.
- **T912** (randomness): A mostly random interior with a visible grain of small triangles and a more regular band along the edges.
- **T2040** (randomness): Random texture broken by dark triangular patches of solid black of various sizes.
- **T138** (randomness): A triangle of irregular white-flecked mottling in gray and black.
- **T867** (randomness): A triangle of bright speckle with a mirror-symmetric, kaleidoscope-like center.
- **T1473** (randomness): A triangle of fine speckle with scattered white triangular gaps.
- **T1929** (randomness): A dark triangle of black-and-gray static with black triangular patches of many sizes.
- **T777** (randomness): A triangle of black-and-white noise with a mirror line down the center and small white triangles scattered through it.
- **K2R2-10** (randomness): Fine random speckle with faint banding.
- **K2R2-50** (randomness): Random speckle dotted with bold black inverted triangles.
- **E90.rand** (randomness): A random field with white triangles at every size; rule 90 adds shifted copies of its single-cell triangle, so the picture carries the initial row's randomness.
- **E90.inject** (randomness): Rule 90 with one random cell injected every step: a dense lace of overlapping triangles at every size.
- **E105.rand** (randomness): Dense black-and-white static with white triangles of many sizes scattered through it.
- **E129.rand** (randomness): A dark field of irregular texture broken by black triangles of many sizes.
- **E22.rand** (randomness): A random field with white triangles whose black density settles near 0.35, coming from the rule itself.
- **E22.seed19** (randomness): From the five cells 10011 the pattern grows a random core of density 0.35 that widens, with repetitive regions on both sides.
- **E126.rand** (randomness): A rule that never settles: random texture at density one half with white triangles at all scales.
- **E126.pairs** (randomness): Random black-black and white-white pairs evolve into a dense field of triangles of many sizes.
- **E90.sparse** (randomness): Sparse speckle at density 0.05 spawns overlapping triangles of every size that pile up into a dense lace, and the thin speckle returns at steps that are powers of two.
- **E150.rand** (randomness): Dense black-and-white static with small dark clumps and no visible structure.
- **E18.rand** (randomness): Sparse speckle with white triangles of many sizes scattered across it.
- **E60.rand** (randomness): A dense random texture crossed by small black and white triangles that lean to the right.
- **E232.rand** (randomness): Vertical bars of random width in black and white, frozen from the first rows.
- **E170.rand** (randomness): Thick diagonal stripes of irregular widths lean to the right.
- **E2.rand** (randomness): Thin diagonal lines lean to the right, scattered at irregular spacing across white.
- **E106.rand** (randomness): A dense field of diagonal black-and-white strokes with white triangles of many sizes scattered through it.
- **E154.rand** (randomness): Dense fine diagonal black-and-white lines cross the field at irregular spacing.
- **T237.rand** (randomness): Dense random black-and-white texture with white triangles of many sizes scattered throughout.
- **T1182.rand** (randomness): A mid-gray mottled field with gray triangles of many sizes.
- **T2046.rand** (randomness): A black field crossed by thin vertical lines of irregular spacing.
- **E225.rand** (randomness): Thin diagonal strokes scattered at irregular spacing across a black field.
- **T1848.rand** (randomness): A black field strewn with white triangle outlines of many sizes.
- **T1932.rand** (randomness): A dark field with white triangles of many sizes.
- **T1410.rand** (randomness): A narrow steep column of dense gray-and-black speckle.
- **K2R2-2.rand** (randomness): Sparse speckle that spawns white triangles of many sizes.
- **K2R2-30.rand** (randomness): Dense speckle with white triangular outlines at many sizes.
- **K2R2-42.rand** (randomness): Dense mottled speckle with small white triangles.
- **K2R2-52.rand** (randomness): Vertical black and gray bars of irregular widths over a white field.
- **E110** (complexity): From a random full-length row the pattern organizes into a regular background of small triangles crossed by localized structures that move at different speeds and collide.
- **E110.rand** (complexity): Within a few steps a random row organizes into a regular background of small triangles crossed by localized structures that move at different speeds and collide.
- **E54.rand** (complexity): From a random row, a regular background crossed by moving localized structures that collide and interact.
- **T1041** (complexity): A mixture of regular vertical stripes and irregular regions.
- **T1599** (complexity): A field of irregular trees and columns that grow, die out and return.
- **T1329.seed54889** (complexity): From seed 54889 a complex region widens by about half a cell per step in total, drifting slowly to one side without bound.
- **T1635** (complexity): Black triangular regions of many sizes separated by textured, irregular zones, with localized structures crossing between them.
- **T1635.rand** (complexity): Black voids and bright textured regions are split by tall branching structures that grow, collide and merge.
- **T2049** (complexity): A large solid black wedge near the center flanked by long vertical lines, with a busy irregular fringe of small structures along both outer sides.
- **T2049.rand** (complexity): A black field with thin gray vertical lines, hung with branching white trees that reach down from above.
- **T1329.rand** (complexity): A white field with gray triangles and black trees that grow downward and collide.
- **T357.rand** (complexity): White voids with gray-and-black trees of many sizes growing into them.
- **T948.rand** (complexity): Bold black-and-white branching structures at diagonal angles that run into each other.
- **T1920.rand** (complexity): Black columns split by bright vertical seams, each filled with nested triangles of its own size.
