# Core/Programs

CPU reference implementations of the cellular automata. They are the ground
truth: the Metal `step` kernels in `Core/Render` must produce identical rows,
and tests compare row hashes.

## Semantics

- A `RowProgram` owns a width-`W` row and advances it by one `step()`.
  Neighborhoods wrap at both edges.
- `stateCount` is the number of cell values (2 for elementary rules, 3 for the
  3-color totalistic rules). Row values are palette indices; index 0 is the
  background.
- `SplitMix64` is the harness PRNG. It is bit-for-bit deterministic so a
  random-start entry (`E54`) matches between CPU and GPU.

## Entries

`ElementaryCA` (Wolfram code, radius 1) and `TotalisticCA` (radius 1, k
colors, base-k code) are taken verbatim from the inventory, section 1. The
per-entry rule numbers, widths, heights, and starts live in `Core/Catalog`.

## Tests

- For each catalog entry, N rows from the CPU program hash to a recorded
  golden value.
- Each elementary rule's closed Boolean form agrees with its rule table for all
  8 neighborhoods (inventory §1.1).
