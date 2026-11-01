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
  size, the per-turn prefilled/cached prompt and generation token counts and
  seconds, the model's raw
  answer, and the parsed class per image); `--quiet`
  keeps only the summary lines, and `--show-prompt` adds the full system
  prompt. `rate` always opens a screen-sized Metal window (the `Core/Render`
  on-screen path: `RenderActor` + `CellGridSink` + a `MetalLayerTarget`; see
  `Core/Render/README.md`). The window's title bar is transparent and carries
  no title, so the page spans the whole window and only the standard traffic
  lights float over it; their close button ends the review, and Cmd-Q (the app
  menu's Quit) does too. It opens on the drawing page. At launch it loads the
  model and runs one minimal image turn at up to 256 px in the background, so
  the vision and decode kernels are compiled before the first submission. When
  an image
  sits beside an `examples.json` reference manifest, its page shows the class it
  illustrates in English and Chinese in the top-left corner; the window draws
  that label and the image the model reads carries no text. Left and
  right arrows move through the carousel: the drawing page, then every image,
  then the drawing page again, so the drawing page is the wrap point at both
  ends. Draw by pressing the pointer down on the page and dragging: the stroke
  runs from the press to the release, moving the pointer without pressing draws
  nothing, and leaving the page during a drag ends the stroke at the edge.
  Return submits the current page: for two seconds the image separates into a
  double exposure — two copies a fraction of its height apart — then the
  doubled screen collapses for half a second onto the dot the collapse intro
  starts from, rejoining the two copies as it shrinks them. The beat's
  shaders compile and its picture uploads while the submitted page is still on
  screen, and the window swaps to the beat only after its first frame has been
  presented, so a submission never shows a blank page. The submission
  beat (`SubmissionTimeline`) and the intro (`CollapseTimeline`) run while the
  model works; if the model outlasts them, the window freezes on the intro's
  rest frame rather than a blank page. Every run draws a fresh variation, so
  the wait never repeats itself. Once the chosen entry is known, an entry that
  seeds from a single centred cell retracts the rest frame onto that cell, so
  the automaton appears to start from the intro's last image; every other entry
  keeps the line. A `.rand` entry redraws from a fresh row each time. The
  reveal then grows the chosen entry as two mirrored branches from that line:
  one branch grows upward and the other downward from the same horizon row.
  Both branches advance together. The reveal opens on a close-up of the seed,
  where one cell is eight of the window's base cells, and the camera zooms out
  from there at the branches' growth rate so the whole growth stays in view.
  At the display floor one cell is one element of the surface; past it the
  camera keeps pulling back by averaging a wider block of the stored history
  into each cell and drawing that average as tone, so the seed stays on the
  horizon and the newest rows stay on the outer edges at decreasing resolution
  instead of older rows leaving through the horizon. The history ring grows with
  the run so no row is dropped. The run opens at 60 source rows per second
  (`.timed`), so each branch fills half the window in 30 rows per second. The
  rate's per-step growth is +0.3% and that growth itself compounds by +0.02%
  each step, so the pull-back is quicker from the first second, doubles its
  speed by about three seconds, and still finishes super-exponentially: a
  screen-sized window (about 2,000 source rows) pulls back in about 5.4 s.
  The window's
  drawable is allocated at the floor's grid size, and the run simulates a board
  ten windows wide, so the pattern keeps evolving after it leaves the first
  view. An entry whose pattern drifts sideways (see `DisplayHints.follow`)
  pans the viewport with it. The reveal has no zoom, speed, restart, or pan
  controls. The pull-back ends where its sampling widens the window to the
  whole board, before the fit would show the page either side of the pattern:
  the panel disappears, the circle closes around the picture — its limb
  eroding — until only a single ink dot remains. The window then advances to
  the next carousel page as Return would. Return on the
  reveal still advances early; closing the window stops the run. The reveal's
  top-left panel puts a thumbnail of the submitted picture beside the chosen
  entry's id and its class in English and Chinese, then the model's English and
  Chinese reasons, so the reasons read as commentary on the picture. The × in
  the panel's top-right corner closes the panel, leaving the automaton alone;
  the window's traffic lights close the review.
  `--model <dir>` (or `RATER_MODEL_PATH`) is required: the engine loads a local
  snapshot and never downloads; see `Agent/README.md`.
- `rater-cli bench <path|dir>...` — the headless measurement path. Preloads the
  model and the system-prefix KV cache, then runs the agent once per image with
  no window or automaton. Prints each image's prefilled/cached prompt and
  generation token counts and seconds plus batch totals. `rate` is the product
  flow; use `bench` to compare a prompt or model change from a script, since
  `rate` blocks on Return. `--image-size <px>` sets the square input dimension
  (default 512), so a single command sweeps the vision-token tradeoff.
- `rater-cli classify <path|dir>...` — the headless accuracy path. Preloads the
  model and system-prefix cache, runs each image once with no window, clears the
  no-repeat window between images so the score measures classification and not
  batch order, and prints `name<TAB>class<TAB>id` plus a class tally, so a
  labeled reference set can be scored against the model.
- `rater-cli catalog` — print the catalog and the generated index.

`catalog` is AppKit-free. `rate` links AppKit to host the window and drives
`Core/Render`'s on-screen sink.

## Window views

- **A panel's padding belongs in its content, not in a frame.**
  `NSGlassEffectView` stretches its `contentView` over its own bounds, so a
  frame set on the content view is discarded on the next layout.
  `PageOverlayView` therefore draws its padding inside its own bounds and
  `LabeledPageView` sizes the panel to that view. The close button is a sibling
  placed in the panel's top-right corner, so `PageOverlayView.closeReserve` must
  keep that corner of the reason row clear of text.
- **The page spans the title bar, which is invisible.** The window is
  `.titled, .closable, .miniaturizable, .resizable` with a transparent title
  bar and a full-size content view, so the traffic lights float over the page
  and stay above every swap, and the green button acts because the window
  resizes. A titled window is key by default, so the key monitor receives
  Return and the arrows without overrides. The buttons sit over the page, so
  `PageOverlayView` adds the title bar's height above its top inset
  (`titlebarClearance(of:)`) and the page's own top-left text starts below
  them; the drawable geometry still comes from the content view's bounds.
- **A `CAMetalLayer` shows nothing until a presented frame reaches it.**
  Give the layer the page background, and swap a layer in only after that: a
  present only lands at the next display update, so `hasPresentedFrame` waits
  for the second one. `CellGridSink` and `WorkingIndicator` report it, and
  `AutomatonWindow` waits on it before every content swap.
- **The reveal's ending samples the picture as one image.**
  `RenderFrame.mask` travels to both draw paths: the tone path samples the
  toned grid through the ending's scale and eroding circle, and the span path
  hides every cell outside that circle. `RenderActor` drives the mask from
  `RevealTimeline` on the clock's own ticks after the pull-back stops, so the
  ending costs one refit and draw per frame and none of it is CPU-driven.

## Remaining work

- **The stroke lifecycle is not tested.** `Drawing`'s value contract is covered
  by `DrawingTests`, but the canvas needs a pointing device and a human, so the
  press-drag-release lifecycle, leaving the page, and the pen following the
  pointer rather than a finger's contact point are accepted by inspection.
