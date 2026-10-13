# Core/Programs

CPU reference implementations of the cellular automata. They are the ground
truth: the Metal `step` kernels in `Core/Render` must produce identical rows,
and tests compare row hashes.

## Semantics

- A `RowProgram` owns a width-`W` row and advances it by one `step()`.
  Neighborhoods wrap at both edges.
- `stateCount` is the number of cell values (2 for elementary and K2R2 rules,
  3 for the 3-color totalistic rules). Row values are palette indices; index 0
  is the background.
- `SplitMix64` is the harness PRNG. It is bit-for-bit deterministic so a
  random-start entry matches between CPU and GPU. Density-one-half rows keep
  the original `next() & 1` draw; other 2-color densities use the top 53 bits,
  so the recorded goldens do not move when a new density is added. A 3-color
  random row draws each of white, gray and black with probability one third
  (inventory §1.4).

## Entries

`ElementaryCA` (Wolfram code, radius 1), `TotalisticCA` (radius 1, k colors,
base-k code), and `K2R2CA` (2 colors, radius 2, 6-bit code) are taken verbatim
from the inventory, section 1. The per-entry rule numbers, widths, heights,
and starts live in `Core/Catalog`. A program built through `ProgramFactory`
takes its seed row from `BoardStart`, so seeds, blocks, non-half densities and
3-color random rows are seeded on the CPU and uploaded by the GPU path
(`MetalSimulation.reseed` reads `spec.makeProgram().row()`).

Injected randomness (`Board.injection`) overwrites the centre cell after every
step with `SplitMix64.injectedValue(seed:step) % stateCount`. The value is a
function of the seed and the step index, not generator state, so the CPU
reference and the Metal `step_*` kernels compute the same injection and stay
row-for-row identical.

## Tests

- For each catalog entry, N rows from the CPU program hash to a recorded
  golden value.
- Each elementary rule's closed Boolean form agrees with its rule table for all
  8 neighborhoods (inventory §1.1).
