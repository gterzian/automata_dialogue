# Core/Catalog

One table of 45 `ProgramSpec` values feeds the renderer, the system prompt's
automata listing, and the CLI catalog debug print. The listing is built from
this table, so what the model chooses and what the renderer draws cannot
diverge.

## Invariants

- Exactly **45** entries, unique ids, in the inventory's order.
- Behavior counts: **repetition 12, nesting 14, randomness 10, complexity 9**.
- Every id appears in `Catalog.ids`, and `Catalog.promptIndexLines` is generated
  from the same table as `id | class | look`.

## Types

- `Behavior` — the four classes: `.repetition`, `.nesting`, `.randomness`,
  `.complexity`. Every entry carries exactly one; the system prompt lists each
  entry with its class instead of grouping.
- `GPUProgram` — `.elementary(rule:)`, `.totalistic(code:colors:)`, or
  `.k2r2(code:)` (radius 2, binary, inventory §1.3); selects the step kernel
  and its constants.
- `Board` — `width`, `height`, `start`. A start is `.center`, `.rightmost`, a
  random row (`.random(seed:density:)`), `.randomBlocks(seed:)`, a repeated
  `.block([UInt8])`, or a `.seed(number:colors:)` written most-significant
  first from the center (inventory §1.4). Widths/heights come from the
  inventory; a start whose pattern would wrap needs a board wide enough for the
  run.
- `DisplayHints` — `stepsPerSecond`, `stepLimit`, `pinRight` (E110 only),
  `palette`.
- `Palette` — up to 16 colors; index 0 is the background. Elementary entries
  use white/black; totalistic entries white/gray/black (inventory §1.2).

## `look`

`ProgramSpec.look` is a one-sentence visual description. It is the matching text
in the system prompt's automata listing and must stay one line.

## `reference`

`ProgramSpec.reference` builds the CPU `RowProgram` for tests and the CPU
renderer. It is the only place that knows how a spec's `GPUProgram`/`Board`
map onto `ElementaryCA`/`TotalisticCA`/`K2R2CA`.
