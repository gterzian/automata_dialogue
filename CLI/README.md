# CLI

`rater-cli`, a SwiftPM executable built against `Core`. Commands:

- `rater-cli rate <path|dir>...` — run the real MLX agent over reference
  drawings and print the chosen id and latency per image, then a summary table.
  A path may be an image file or a directory, in which case its top-level
  images are rated (so `rate artifacts/` runs every drawing in the folder).
  Each image is normalized to the model's input through `Core/Import` (512×512
  by default; `--image-size <px>` overrides it). The engine
  keeps its recent-choice window across the batch, so each image is asked to
  pick an automaton the earlier images did not. Debug
  output is on by default (the resolved model, the prompt
  size, the per-turn prompt/generation token counts and seconds, the model's raw
  answer, and the parsed class per image); `--quiet`
  keeps only the summary lines, and `--show-prompt` adds the full system
  prompt. `rate` always opens a screen-sized Metal window (the `Core/Render`
  on-screen path: `RenderActor` + `CellGridSink` + a `MetalLayerTarget`; see
  `Core/Render/README.md`). The window opens on the drawing page. Left and
  right arrows move through the carousel: the drawing page, then every image,
  then the drawing page again, so the drawing page is the wrap point at both
  ends. Draw by pressing the pointer down on the page and dragging: the stroke
  runs from the press to the release, moving the pointer without pressing draws
  nothing, and leaving the page during a drag ends the stroke at the edge.
  Return submits the current page: for two seconds the image separates into a
  double exposure — two copies a fraction of its height apart — then the
  doubled screen collapses for half a second onto the dot the collapse intro
  starts from, rejoining the two copies as it shrinks them. The submission beat
  (`SubmissionTimeline`) and the intro (`CollapseTimeline`) run while the model
  works; if the model outlasts them, the window freezes on the intro's rest
  frame rather than a blank page. Every run draws a fresh variation, so the wait
  never repeats itself. Once the chosen entry is known, an entry that seeds from
  a single centred cell retracts the rest frame onto that cell, so the automaton
  appears to start from the intro's last image; every other entry keeps the
  line. A `.rand` entry redraws from a fresh row each time. The reveal then
  grows the chosen entry as two mirrored branches from that line: one branch
  grows upward and the other downward from the same horizon row. Both branches
  advance together, and the camera zooms out continuously at the branches'
  growth rate so the whole growth stays in view.
  At the display floor one cell is one element of the surface; past it the
  camera keeps pulling back by reducing a wider block of the stored history per
  cell, so the seed stays on the horizon and the newest rows stay on the outer
  edges at decreasing resolution instead of older rows leaving through the
  horizon. The history ring grows with the run so no row is dropped. The run
  starts at 40 source rows per second (`.timed`); each branch fills half the
  window, so the visible growth speed matches a single run at 20. The
  window's drawable is allocated at the floor's grid size, and the run simulates
  a board ten windows wide, so the pattern keeps evolving after it leaves the
  first view. An entry whose pattern drifts sideways (see `DisplayHints.follow`)
  pans the viewport with it. The reveal has no zoom, speed, restart, or pan
  controls. Return on the reveal advances to the next carousel page; closing
  the window stops the run.
  `--model <dir>` (or `RATER_MODEL_PATH`) is required: the engine loads a local
  snapshot and never downloads; see `Agent/README.md`.
- `rater-cli bench <path|dir>...` — the headless measurement path. Runs the
  agent once per image with no window or automaton, then prints each image's
  prompt/generation token counts and seconds plus batch totals. `rate` is the
  product flow; use `bench` to compare a prompt or model change from a script,
  since `rate` blocks on Return. `--image-size <px>` sets the square input
  dimension (default 512), so a single command sweeps the vision-token
  tradeoff.
- `rater-cli classify <path|dir>...` — the headless accuracy path. Runs each
  image once with no window, clears the no-repeat window between images so the
  score measures classification and not batch order, and prints
  `name<TAB>class<TAB>id` plus a class tally, so a labeled reference set can be
  scored against the model.
- `rater-cli catalog` — print the catalog and the generated index.

`catalog` is AppKit-free. `rate` links AppKit to host the window and drives
`Core/Render`'s on-screen sink.

## Remaining work

- **The stroke lifecycle is not tested.** `Drawing`'s value contract is covered
  by `DrawingTests`, but the canvas needs a pointing device and a human, so the
  press-drag-release lifecycle, leaving the page, and the pen following the
  pointer rather than a finger's contact point are accepted by inspection.
