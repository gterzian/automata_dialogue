# CoreTests

XCTest coverage for `Core`, run with `swift test`. No live model and no GPU:
Metal kernel tests are skipped unless `MTLCreateSystemDefaultDevice()` reports
Metal 4.

What must be covered:

- **Catalog** — 111 unique ids in inventory order; behavior counts
  (repetition 29, nesting 28, randomness 40, complexity 14); the listing and the
  catalog ids agree; per-entry follow rates, and which seed rows are a single
  centred cell.
- **Prompt** — `SystemPrompt.build` embeds every catalog id with its class,
  describes all four classes, states the answer format, and stays within the
  ~4k budget.
- **Choice** — the parser (`id:` field, markdown, prose fallback, longest-id
  match, unknown id) and the recent-choice window (limit, exclusion note).
- **Import** — normalization writes a 512×512 PNG; temp lifecycle.
- **Render seam** — `RenderActor` runs off the main thread, delivers GPU
  frames, and advances on clock ticks; the pacing math; (Metal 4 only) the GPU
  seed shapes, a growing run, the window follow, a zoom refit, zoom's grid
  resize, and the twin run's mirrored branches, step count, and reported
  horizon row.
- **Viewport** — `ViewportGeometry` columns/rows, the ten-window board width,
  the centred or rightmost start origin, the visible span under zoom, the twin
  grid's shared horizon row, and the display-dependent zoom floor.
- **Reveal camera** — `RevealCamera` starts at 1×, never zooms in, matches the
  branches' growth one for one, keeps the newest row visible above the floor,
  and holds the floor once the growth fits.
- **Layer sink** — (Metal 4 only) an offscreen render fills each span with its
  palette colour, a renderer handles a grid resize, and the sink serializes
  frames that share buffers.
- **Collapse intro** — the timeline's phase boundaries, the rest frame the
  clock freezes on, the seed-cell retraction, that a seed reproduces one run's
  look and two seeds disagree, and that every phase reaches the renderer.
  Appearance is reviewed by hand.
