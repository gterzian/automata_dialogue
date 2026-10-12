# CLI

`rater-cli`, a SwiftPM executable built against `Core`. Commands:

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
  prompt. `--show` shows each input image in the window while the model runs,
  then opens the chosen automaton in that window (rendered by `Core/Render`'s
  on-screen path: `RenderActor` + `LayerSink` + `DisplayLinkClock`, the same
  Metal renderer the app is wired to). It redraws a `.rand` entry from a fresh
  row each time, and waits for the window to be closed before processing the
  next image; without it the batch is headless.
  `--model <dir>` (or `RATER_MODEL_PATH`) is required: the engine loads a local
  snapshot and never downloads; see `Agent/README.md`.
- `rater-cli catalog` — print the catalog and the generated index.
- `rater-cli hashes` / `rater-cli cells <id> <steps>` — golden row hashes and a
  single row's cells, for kernel debugging.
- `rater-cli gpu <id> --cols N --rows N --steps N` — run the Metal 4 `step` and
  `fit` kernels for one entry and report whether the grid matches the CPU
  reference.

Everything except `rate --show` is AppKit-free: those commands use
`Core/Import` and `Core/Render` directly. `rate --show` links AppKit to host the
window and drives `Core/Render`'s on-screen sink.
