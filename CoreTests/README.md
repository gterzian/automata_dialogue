# CoreTests

XCTest coverage for `Core`, run with `swift test`. No live model and no GPU:
Metal kernel tests are skipped unless `MTLCreateSystemDefaultDevice()` reports
Metal 4.

What must be covered:

- **Catalog** — exactly 45 unique ids in inventory order; behavior counts
  (repetition 12, nesting 14, randomness 10, complexity 9); the dispatcher's
  label→ids listing and the catalog ids agree.
- **Programs** — CPU reference row hashes for each entry; closed-form local
  rules agree with the rule table for all 8 neighborhoods; the K2R2 code table.
- **Prompt** — `SystemPrompt.build` contains every rubric section and no
  catalog id; the prefix stays within budget.
- **Dispatcher** — ordering (`rate → list → choose` and each call out of
  order), label-scoped listing, argument and id validation, event emission,
  loop bound.
- **Import** — normalization writes a 512×512 PNG; temp lifecycle.
- **Transcript** — store append/apply/rebuild, `StreamingRefreshGate`, and
  `HeightCache` behavior.
- **Render seam** — `ReadbackSink`/`SinkFactory` behavior, `RenderActor` runs
  off the main thread, and (Metal 4 only) the GPU incremental frames equal
  `IncrementalRenderer` for a partial run.
- **Layer sink** — (Metal 4 only) the `runs` span compaction equals a CPU
  run-length pass, and an offscreen render fills each span with its palette
  colour.
