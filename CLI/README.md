# CLI

`rater-cli`, a SwiftPM executable built against `Core`. Two commands:

- `rater-cli render <id> --frames N --out <dir>` — headless render of a
  catalog entry to PNG frames, using the CPU reference programs. Used to
  eyeball the catalog and to produce golden images.
- `rater-cli rate <path|dir>...` — run the real MLX agent over reference
  drawings and print the chosen id and latency per image, then a summary table.
  A path may be an image file or a directory, in which case its top-level
  images are rated (so `rate artifacts/` runs all six). Each image is
  normalized to the model's 512×512 input through `Core/Import`, the same path
  the app uses. The engine keeps its recent-choice window across the batch, so
  each image is asked to pick an automaton the earlier images did not. Debug
  output is on by default (the resolved model, the prompt
  size, the model's raw answer, and the parsed class per image); `--quiet`
  keeps only the summary lines, and `--show-prompt` adds the full system
  prompt. `--model <dir>` (or `RATER_MODEL_PATH`) loads a local snapshot instead
  of downloading; see `Agent/README.md`. This needs the `Agent` target: the
  SwiftPM CLI has it only when built with `RATER_AGENT=1`, the Xcode scheme
  always. See `AGENTS.md`.
- `rater-cli catalog` — print the catalog and the generated index.
- `rater-cli hashes` / `rater-cli cells <id> <steps>` — golden row hashes and a
  single row's cells, for kernel debugging.
- `rater-cli gpu <id> --cols N --rows N --steps N` — run the Metal 4 `step` and
  `fit` kernels for one entry and report whether the grid matches the CPU
  reference.

The CLI never links AppKit; it uses `Core/Import` and `Core/Render` directly.
