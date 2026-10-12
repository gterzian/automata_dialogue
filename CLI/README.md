# CLI

`rater-cli`, a SwiftPM executable built against `Core`. Commands:

- `rater-cli render <id> [--out file.png]` — headless render of a catalog
  entry to a PNG, using the CPU reference programs. Used to eyeball the
  catalog and to produce golden images. `--all [--out dir]` renders every
  entry; `--cols`, `--rows`, and `--steps` override the size and step count.
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
  prompt. `rate` always opens a screen-sized Metal window (the `Core/Render`
  on-screen path: `RenderActor` + `LayerSink` + `DisplayLinkClock`, the path
  the app should adopt; see `Core/Render/README.md`). It shows the submitted
  image until Return,
  runs the model, scrolls the chosen automaton until the next Return, and
  cycles the images until the window is closed. While the model runs the
  window shows `WorkingIndicator` (Metal beating rings) in place of the
  image, so the wait is visibly "working". A `.rand` entry redraws from a
  fresh row each time. The window's drawable holds one cell per display column
  (`ViewportGeometry`), and the run simulates a board ten windows wide: the
  layer stretches a small cell grid over the whole window while the viewport
  shows one part of a much bigger board, so the pattern keeps evolving after it
  leaves the first view and each Left/Right arrow moves the viewport ten
  columns; Escape restarts the running automaton from a fresh seed; Up/Down
  raise or lower the growth rate (each press ×1.5). The run starts at 20 rows
  per second of wall time (`.timed`) and advances toward the bottom until the
  window fills, then scrolls with the newest row at the bottom and older rows
  going off the top.
  `--model <dir>` (or `RATER_MODEL_PATH`) is required: the engine loads a local
  snapshot and never downloads; see `Agent/README.md`.
- `rater-cli catalog` — print the catalog and the generated index.
- `rater-cli hashes` / `rater-cli cells <id> <steps>` — golden row hashes and a
  single row's cells, for kernel debugging.
- `rater-cli gpu <id> --cols N --rows N --steps N` — run the Metal 4 `step` and
  `fit` kernels for one entry and report whether the grid matches the CPU
  reference.

Everything except `rate` is AppKit-free: those commands use
`Core/Import` and `Core/Render` directly. `rate` links AppKit to host the
window and drives `Core/Render`'s on-screen sink.
