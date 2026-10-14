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

`example_*.png` are the drawings used to re-check the model when the prompt or
a snapshot changes (`Agent/README.md`, `rater-cli classify`). The table records
the class each drawing illustrates, so the set can be scored without re-reading
the images. `example_7.png` (a photograph of light trails) and `example_8.png`
(crossing line segments that close into polygons) are the borderline cases
between `complexity` and `randomness`; either class is defensible, so they are
the drawings to watch when the rubric changes.

| file | class | what it shows |
|---|---|---|
| `example_1.png` | repetition | three parallel diagonal lines at even spacing |
| `example_2.png` | complexity | crossing lines with shapes meeting at the intersections |
| `example_3.png` | complexity | a calligraphy glyph of interacting strokes |
| `example_4.png` | nesting | one triangle at three scales |
| `example_5.png` | complexity | crossing lines with triangles and circles at the intersections |
| `example_6.png` | repetition | one plain circle |
| `example_7.png` | randomness (borderline) | long-exposure light trails |
| `example_8.png` | complexity (borderline) | crossing line segments that close into polygons |
| `example_9.png` | randomness | a busy tangle of random strokes |
| `example_10.png` | randomness | scattered dots with accidental clusters |
| `example_11.png` | randomness | a meandering scribble |
| `example_12.png` | complexity | a house, a recognizable subject |
| `example_13.png` | nesting | one square at five scales |
| `example_14.png` | repetition | one cross repeated on a regular grid |
