# CoreTests

XCTest coverage for `Core`, run with `swift test`. No live model and no GPU:
Metal kernel tests are skipped unless `MTLCreateSystemDefaultDevice()` reports
Metal 4.

What must be covered:

- **Catalog** — 111 unique ids in inventory order; behavior counts
  (repetition 29, nesting 28, randomness 40, complexity 14); the listing and the
  catalog ids agree; per-entry follow rates, and which seed rows are a single
  centred cell.
- **Prompt** — `SystemPrompt.build` embeds every catalog id under its class
  heading, describes all four classes, states that complexity requires both an
  ordered and a disordered part (so a recognizable figure such as the house is
  repetition), states the answer format in both languages, and stays within the
  ~4k budget.
- **Choice** — the parser (`id:` field, English and Chinese reasons, full-width
  colon, markdown, prose fallback, longest-id match, unknown id), the
  recent-choice window (limit, exclusion note), `AgentDialogue`'s turn and
  accept/reject rules, `AgentBackend`'s argument parsing, and the reusable
  prompt prefix (shared tokens, stopped at the first image placeholder).
- **Import** — normalization writes a 512×512 PNG; temp lifecycle; a blank
  drawing is a uniform raster while a stroke reaches the raster; aspect-fit
  keeps a wide drawing's shape; a drawing normalizes to a square PNG; reference
  labels come from the directory manifest and match the artifact README table.
- **Render seam** — `RenderActor` runs off the main thread, delivers GPU
  frames, and advances on each frame its target delivers; the pacing math;
  (Metal 4 only) the GPU
  seed shapes, a growing run, the window follow, a zoom refit, zoom's grid
  resize, a display cell below the floor keeping its block's average colour,
  and the twin run's mirrored branches, step count,
  reported horizon
  row, and seed row staying on the horizon past the display floor.
- **Viewport** — `ViewportGeometry` columns/rows, the ten-window board width,
  the centred or rightmost start origin, the visible span under zoom, the twin
  grid's shared horizon row, the display-dependent zoom floor (from a display's
  pixels and from a fixed-resolution surface's elements), and the sampling
  stride past it.
- **Reveal camera** — `RevealCamera` opens at its close-up, holds it while the
  branch has room, then matches the branches' growth one for one and keeps
  pulling back below the display floor; the review window's first frame is
  already at that close-up.
- **Cell grid sink** — (Metal 4 only) an offscreen render fills each span with
  its palette colour, a toned grid is drawn with its cells' own colours, a
  renderer handles a grid resize, the sink draws into
  whichever `RenderTarget` it is given and takes that target's limits and pixel
  format, a layer target has no surface before its first display-link update,
  and the sink serializes frames that share buffers.
- **Collapse intro and submission beat** — the rest frame the reveal continues
  from, the opening frame the beat lands on, the beat's part-and-collapse
  phases, the seed-cell retraction, that a seed reproduces one run, that
  the cycle, the beat, and the retraction reach their renderers, and that the
  intro draws through the target it is given. Appearance is accepted by visual
  inspection.
