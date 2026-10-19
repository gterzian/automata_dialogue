# CoreTests

XCTest coverage for `Core`, run with `swift test`. No live model and no GPU:
Metal kernel tests are skipped unless `MTLCreateSystemDefaultDevice()` reports
Metal 4.

What must be covered:

- **Catalog** — 111 unique ids in inventory order; behavior counts
  (repetition 29, nesting 28, randomness 40, complexity 14); the listing and the
  catalog ids agree; per-entry follow rates.
- **Prompt** — `SystemPrompt.build` embeds every catalog id with its class,
  describes all four classes, states the answer format, and stays within the
  ~4k budget.
- **Choice** — the parser (`id:` field, markdown, prose fallback, longest-id
  match, unknown id) and the recent-choice window (limit, exclusion note).
- **Import** — normalization writes a 512×512 PNG; temp lifecycle.
- **Render seam** — `RenderActor` runs off the main thread, delivers GPU
  frames, and advances on clock ticks; the pacing math; (Metal 4 only) the GPU
  seed shapes, a growing run, the window follow, a zoom refit, and zoom's grid
  resize.
- **Viewport** — `ViewportGeometry` columns/rows, the ten-window board width,
  the centred or rightmost start origin, and the visible span under zoom.
- **Layer sink** — (Metal 4 only) an offscreen render fills each span with its
  palette colour, a renderer handles a grid resize, and the sink serializes
  frames that share buffers.
- **Collapse intro** — the ten-second timeline freezes on its final frame; a
  seed always reproduces one run's look and two seeds disagree; (Metal 4 only)
  the discs and rays draw, different times paint different frames, the opening
  point's edge ramps over several pixels, the ending goes mostly black, and the
  black field then shrinks into a bare white page.
