# CLI

`rater-cli`, a SwiftPM executable built against `Core`. Two commands:

- `rater-cli render <id> --frames N --out <dir>` — headless render of a
  catalog entry to PNG frames, using the CPU reference programs. Used to
  eyeball the catalog and to produce golden images.
- `rater-cli rate <path>...` — run the real MLX agent over a folder of
  reference drawings and print rating, choice, and latency per image, then a
  summary table. This needs the `Agent` target: the SwiftPM CLI has it only
  when built with `RATER_AGENT=1`, the Xcode scheme always. See `AGENTS.md`
  and `Agent/README.md`.
- `rater-cli catalog` — print the catalog and the generated prompt index.
- `rater-cli hashes` / `rater-cli cells <id> <steps>` — golden row hashes and a
  single row's cells, for kernel debugging.
- `rater-cli gpu <id> --cols N --rows N --steps N` — run the Metal 4 `step` and
  `fit` kernels for one entry and report whether the grid matches the CPU
  reference.

The CLI never links AppKit; it uses `Core/Import` and `Core/Render` directly.
