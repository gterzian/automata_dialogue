# Core/Catalog

One table of 109 `ProgramSpec` values feeds the renderer, the system prompt's
automata listing, and the CLI catalog debug print. The listing is built from
this table, so what the model chooses and what the renderer draws cannot
diverge.

## Invariants

- 109 entries, unique ids, in the inventory's order.
- Behavior counts: **repetition 32, nesting 28, randomness 29, complexity 20**.
- Every id appears in `Catalog.ids`, and `Catalog.promptIndexLines` is generated
  from the same table as `id | class | look`.

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
  continuously injected randomness on top of the start (see `Programs/README.md`).
  Widths/heights are chosen per entry so
  a run fills the frame before it wraps; a start whose pattern would reach the
  ring edge needs a board wide enough for the run (inventory §1.1).
- `DisplayHints` — `stepsPerSecond`, `stepLimit`, `pinRight` (E110 only),
  `follow`, `palette`. `follow` is the review window's sideways tracking rate
  for a drifting pattern; `.none` keeps the view fixed and a manual pan aborts
  it (see `Render/README.md`).
- `Palette` — up to 16 colors; index 0 is the background. Elementary entries
  use white/black; totalistic entries white/gray/black (inventory §1.2).

## `look`

`ProgramSpec.look` is a one-sentence visual description. It is the matching text
in the system prompt's automata listing and must stay one line.

## `reference` and per-run seeds

`ProgramSpec.reference` is a `(Board) -> any RowProgram`; the catalog routes it
through `ProgramFactory`, the one place that maps a spec's
`GPUProgram`/`Board` onto `ElementaryCA`/`TotalisticCA`/`K2R2CA`.
`makeProgram()` builds from the stored board and is deterministic, so it is the
entry point for the golden hashes and the CPU/GPU comparison.

`ProgramSpec.withRandomSeed(_:)` returns a copy whose `.rand` start uses the
given seed; any other start is returned unchanged. The CLI calls it once per run
so re-showing a `.rand` entry gives a different picture (inventory §1.4),
without moving the deterministic `makeProgram()` that the tests pin. It also
reseeds an entry's `injection`, so an `.inject` entry redraws each run the same
way.
