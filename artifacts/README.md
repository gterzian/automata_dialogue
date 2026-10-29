# artifacts

Source material.

- `Curated Inventory of Cellular Automata.md` — the four behavior classes and
  the 111 entries (id, look, class). `Core/Agent/SystemPrompt` is built from the
  same entries.
- `System prompt_ choosing an automaton.md` — the source for
  `Core/Agent/SystemPrompt.swift`.

The four class names describe the **picture** each entry draws from its stated
start, not the rule's class in Wolfram's classification (NKS ch. 6). The
catalog follows the picture where they differ: a class-4 rule reads as
`repetition` when its chosen start is periodic (`T1662`; K2R2 code 20 seed 195,
whose period-22 fixed structure NKS shows on p. 283), and `randomness` also
covers class-2 pictures whose fixed marks are scattered irregularly
(`E232.rand`).

## Reference set

`example_*.png` are white drawings on a black page, the same page the drawing
tool exports. They are the drawings used to re-check the model when the prompt
or a snapshot changes (`Agent/README.md`, `rater-cli classify`). The table
records the class each drawing illustrates, so the set can be scored without
re-reading the images. `examples.json` is the class column in machine-readable
form: `rater-cli rate` reads the manifest beside the images to label each
carousel page with the class it illustrates. The label exists only in the
window, never in the pixels, so the model reads the drawing without it. The
table and the manifest are edited together; `CoreTests` fails when they drift.

Four rows guard the `complexity` boundary. `example_7.png` (flowing trails
crossed by a knot) is the mixed case: an ordered part and a disordered part in
one picture. `example_8.png` (crossing line segments) is one kind of stroke
with no regular part, so it is randomness even where the segments close into
polygons. `example_3.png` (a glyph) and `example_12.png` (a house) are wholly
ordered, recognizable figures, so they are repetition and not complexity.

| file | class | what it shows |
|---|---|---|
| `example_1.png` | repetition | three parallel diagonal lines at even spacing |
| `example_2.png` | complexity | crossing lines with localized shapes at the intersections |
| `example_3.png` | repetition | a glyph: one figure, wholly ordered |
| `example_4.png` | nesting | one triangle at three scales |
| `example_5.png` | complexity | crossing lines with ordered chains of triangles and circles |
| `example_6.png` | repetition | one plain circle |
| `example_7.png` | complexity | flowing light trails with a dense knot of trails |
| `example_8.png` | randomness | crossing line segments of one kind that close into polygons |
| `example_9.png` | randomness | a busy tangle of random strokes |
| `example_10.png` | randomness | scattered dots with accidental clusters |
| `example_11.png` | randomness | a meandering scribble |
| `example_12.png` | repetition | a house: a few plain shapes joined into one settled figure |
| `example_13.png` | nesting | one square at five scales |
| `example_14.png` | repetition | one cross repeated on a regular grid |
