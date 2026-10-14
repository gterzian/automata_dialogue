# Core/Catalog

One table of 111 `ProgramSpec` values feeds the renderer, the system prompt's
automata listing, and the CLI catalog debug print. The listing is built from
this table, so what the model chooses and what the renderer draws cannot
diverge.

## Invariants

- 111 entries, unique ids, in the inventory's order.
- Behavior counts: **repetition 29, nesting 28, randomness 40, complexity 14**.
- Every id appears in `Catalog.ids`, and `Catalog.promptIndexLines` is generated
  from the same table as `id | class`.

## Types

- `Behavior` — the four classes: `.repetition`, `.nesting`, `.randomness`,
  `.complexity`. Every entry carries exactly one; the system prompt lists each
  entry with its class instead of grouping.
- `GPUProgram` — `.elementary(rule:)`, `.totalistic(code:colors:)`, or
  `.k2r2(code:)` (radius 2, binary, inventory §1.3); selects the step kernel
  and its constants.
- `Board` — `width`, `height`, `start`, and optional `injection`. A start is
  `.center`, `.rightmost`, a
  random row (`.random(seed:density:)`), `.randomBlocks(seed:)`, a repeated
  `.block([UInt8])`, or a `.seed(number:colors:)` written most-significant
  first from the center (inventory §1.4). `injection` adds the atlas's
  continuously injected randomness on top of the start (see `Render/README.md`).
  Widths/heights are chosen per entry so
  a run fills the frame before it wraps; a start whose pattern would reach the
  ring edge needs a board wide enough for the run (inventory §1.1).
- `DisplayHints` — `stepsPerSecond`, `stepLimit`, `pinRight` (E110 only),
  `follow`, `palette`. `follow` is the review window's sideways tracking rate
  for a drifting pattern; `.none` keeps the view fixed, and the view scrolls
  only once the pattern's leading edge reaches the viewport boundary (see
  `Render/README.md`).
- `Palette` — up to 16 colors; index 0 is the background. Elementary entries
  use white/black; totalistic entries white/gray/black (inventory §1.2).

## `look`

`ProgramSpec.look` is a one-sentence visual description that stays in sync with
the inventory artifact (`testInventoryMatchesCatalog`). It is not submitted in
the system prompt, which lists only `id | class`: the class is what the model
matches, and keeping the 111 sentences out of the prompt holds the prefill to
~1k tokens. It must stay one line.

## Per-run seeds

The seed row is built on the GPU by `MetalSimulation`'s `seed_row` kernel from
the board's `BoardStart`; the catalog carries no CPU program.

`ProgramSpec.withRandomSeed(_:)` returns a copy whose `.rand` start uses the
given seed; any other start is returned unchanged. The CLI calls it once per run
so re-showing a `.rand` entry gives a different picture (inventory §1.4). It
also reseeds an entry's `injection`, so an `.inject` entry redraws each run the
same way.
