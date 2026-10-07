# CoreTests

XCTest coverage for `Core`, run with `swift test`. No live model and no GPU:
Metal kernel tests are skipped unless `MTLCreateSystemDefaultDevice()` reports
Metal 4.

What must be covered:

- **Catalog** — exactly 32 unique ids in inventory order; behavior counts
  (repetition 9, nesting 11, randomness 6, complexity 6); the schema enum, the
  prompt index, and the catalog ids all agree.
- **Programs** — CPU reference row hashes for each entry; closed-form local
  rules agree with the rule table for all 8 neighborhoods.
- **Prompt** — `SystemPrompt.build` contains all 32 ids and every rubric
  section; the prefix stays within budget.
- **Dispatcher** — ordering (including both calls in one pass), argument and
  id validation, event emission, loop bound, follow-up for a missing call.
- **Import** — normalization writes a 512×512 PNG; temp lifecycle.
- **Transcript** — store append/apply/rebuild, `StreamingRefreshGate`, and
  `HeightCache` behavior.
- **Render seam** — `ReadbackSink`/`SinkFactory` behavior, `RenderActor` runs
  off the main thread, and (Metal 4 only) the GPU incremental frames equal
  `IncrementalRenderer` for a partial run.
- **Layer sink** — (Metal 4 only) the `runs` span compaction equals a CPU
  run-length pass, and an offscreen render fills each span with its palette
  colour.
