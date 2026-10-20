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
  on-screen path: `RenderActor` + `LayerSink` + `DisplayLinkClock`; see
  `Core/Render/README.md`). It shows the submitted
  image until Return,
  runs the model, shows the chosen automaton until the next Return, and
  cycles the images until the window is closed. While the model runs the
  window shows the collapse intro (`CollapseTimeline`): a sub-pixel point fades
  in and grows into a shaded sphere, the frame whites out, a new ink point
  blooms to cover the screen, collapses into a straight horizontal line, and
  thins to a hairline. Every run redraws the intro with its own timings,
  geometry, colour, and grain, so the wait never repeats itself. The
  twelve-second sequence ends on the horizon line: the opening sphere and
  whiteout take the first five seconds, then the bloom, flicker, collapse,
  rebound, and thinning fill the rest. The sequence holds that final line until
  inference finishes, and the automaton is shown only after it has been
  presented, so a fast model does not cut off the ending. The reveal grows the
  horizon row in from that hairline over its first half second.
  A `.rand` entry redraws from a fresh row each time. The reveal then grows the
  chosen entry as two mirrored branches from that line: one branch grows upward
  and the other downward from the same horizon row. Both branches advance
  together, and the camera zooms out continuously at the branches' growth rate
  so the whole growth stays in view, down to the widest zoom-out the display can
  show one cell per element. Once the floor is reached the zoom holds while the
  branches keep growing, and older rows leave through the horizon until Return.
  The run starts at 40 source rows per second (`.timed`); each branch fills half
  the window, so the visible growth speed matches a single run at 20. The
  window's drawable is allocated at the floor's grid size, and the run simulates
  a board ten windows wide, so the pattern keeps evolving after it leaves the
  first view. An entry whose pattern drifts sideways (see `DisplayHints.follow`)
  pans the viewport with it. The reveal has no zoom, speed, restart, or pan
  controls.
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
