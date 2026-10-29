# AGENTS.md — Automata Rater

Automata Rater: a macOS CLI where a local agent chooses one of 111
curated cellular automata to display for an input. The catalog and rubric live
in the two artifacts in `artifacts/`.

## Product intent

The unit of the product is a **dialogue**, not a lookup. Each submission is the
user showing something; the CLI answers in the shared language of complexity by
choosing an automaton whose class of behavior matches. Two consequences drive
design decisions:

- **Variety is required.** The agent keeps a sliding window of the last 20
  choices across runs and puts them in the **user** turn as an exclusion list
  (never the system prompt, which must stay a cacheable prefix). Repeating an
  automaton breaks the illusion of dialogue, so the model must pick an unused
  one. See `ChoiceHistory` in `Core/Agent`.
- **Occasional mis-rating is acceptable.** This is an evocative exchange, not a
  scientific classifier: match at the level of the class of behavior, not
  visual likeness, and do not chase per-image correctness at the cost of the
  dialogue.

The catalog is the vocabulary: the four behavior classes
(`repetition`/`nesting`/`randomness`/`complexity`) are what both sides talk in.

**Optimization target.** Pick the model and prompt with the best blend of low
latency, accuracy, and **diversity of output**, biased toward low latency and
diversity: latency is what makes the exchange feel live, and repeating an
automaton breaks the dialogue outright, while an occasional off-class choice is
acceptable. So prefer a faster, varied model over a slower, slightly more
accurate one. Re-run the reference set (`artifacts/example_*.png`) whenever the
prompt or model changes, and read both numbers when comparing backends:
`rater-cli classify artifacts/` for class agreement and `rater-cli bench
artifacts/` for prefill and generation cost. See `Agent/README.md`.

## Rule Number One

Only perform an action that directly relates to a coding task in this
repository.

## Rule Number Two: Network

Never make network requests to external hosts without explicit prior approval.
Use local resources only, and take approval host by host: GitHub is approved for
cloning reference repositories into `/tmp`. `huggingface.co` and `pypi.org` do
answer from this network, so exporting a model is possible — but only after the
host is approved for it, and nothing downloads by itself.

## File-system boundaries

Read and write freely within this repository and the system temp directories.
Anywhere else requires explicit user approval before a write, move, or delete.

## Documentation Chain

Read documentation from general to specific, in this order:

1. `AGENTS.md` (this file).
2. Every `README.md` found by walking from the repository root down to the
   directory containing the file(s) your task touches, in that order.

Concatenated, they are the "doc chain" for a task. Reading the chain is always
preferred over relying on memory.

### The placement invariant

Every `README.md` sits at the **lowest point in the tree that still covers all
the code beneath it**. Before adding or editing guidance, ask:

- **True for everything below this directory, and only things below it?** If a
  sibling directory needs the same rule, the guidance is too specific — move it
  up, or let the parent cover it.
- **Applies only to a subset below this directory?** It is too broad — move it
  down to the README that owns that subset, or add a new lower README.

`AGENTS.md` is above everything, so anything placed here is claimed to apply
repo-wide.

### Duplication rule

Do not duplicate guidance between a README and any README above it in the same
chain (including `AGENTS.md`). A task that loads the lower README always loads
the higher one. If a lower README needs something explained above it, point to
the file that owns it ("see `Core/Catalog/README.md`") rather than restating it.

### Artifacts and code stay in sync

`artifacts/Curated Inventory of Cellular Automata.md` and
`Core/Catalog/Catalog.swift` are two views of one table; likewise
`artifacts/System prompt_ choosing an automaton.md` and
`Core/Agent/SystemPrompt.swift` are two views of one prompt. The artifact is
the human-readable reference, the Swift is what runs, and nothing generates one
from the other. A change to either side must be mirrored by hand in the same
change, along with the affected tests, counts, and READMEs.

### Keeping the chain sharp and current

- Keep guidance general and durable. One-off implementation details belong in
  the source or its tests, not in repository docs.
- State a rule once, at the level that covers every subject of it, phrased as
  an operational test rather than an adjective ("be clear" says nothing about
  how to tell a violation from the allowed case). A rule's own examples must
  obey it.
- When a rule is tightened after a violation, collapse any duplicate or vaguer
  restatement of it rather than adding another copy, and cross-reference the
  one sharp statement from the places that used to state it.
- When editing a README, check whether the same fact now also lives above it
  in the chain; if so, collapse to one copy at the level the placement
  invariant dictates.

## Build and test

- **`xcodebuild` does not work in this sandbox.** Build and test with SwiftPM:
  - `swift build --disable-sandbox -c release` — builds `Core`, `Agent`, and
    `rater-cli`. **Anything the user runs** is a release build, so the CLI is at
    `.build/release/rater-cli`.
  - `swift test --disable-sandbox` — runs the unit tests.
  SwiftPM's own sandbox cannot apply here, so the flag is required; plain
  `swift build`/`swift test` fail with `sandbox_apply: Operation not
  permitted` before compiling anything.
- A documentation-only change needs no build or test; run them when source,
  tests, or `Package.swift` change.
- To see only warnings from this repo's targets (the agent dependency trees
  emit their own warnings from `.build/checkouts`):
  `swift build --disable-sandbox -c release 2>&1 | grep warning: | grep -v .build/checkouts`.
- The `Agent` target links `mlx-swift-lm`'s C++/Metal build and the
  `AgentCoreAI` target links `coreai-models`'s C++ `xgrammar` bridge, so every
  SwiftPM command builds both. The MLX one needs Xcode's Metal toolchain
  component (`xcodebuild -downloadComponent MetalToolchain`); without it the
  `metal` shim has no compiler and `Cmlx` fails. The component is mounted under a
  path that names the mount, and SwiftPM caches that path in
  `.build/out/Intermediates.noindex/XCBuildData`, so after a boot the build can
  fail with `unable to spawn process …/Metal.xctoolchain/usr/bin/metal (No such
  file or directory)` while `xcrun --find metal` resolves. Delete
  `.build/out/Intermediates.noindex/XCBuildData` and rebuild to pick up the new
  mount. If the link instead fails with
  undefined `_mlx_*` symbols, the `mlx-swift` checkout's `mlx-c` submodule is
  empty; populate it once with `git -C .build/checkouts/mlx-swift submodule
  update --init Source/Cmlx/mlx-c`.
- **A model whose Metal kernels are not yet cached must first run outside the
  sandbox.** MLX compiles its Metal kernels on first use and writes
  the frontend module cache under `/var/folders/…/C/com.apple.metalfe`, which
  the sandbox cannot write; a fresh run traps with `Unable to build metal
  library from source … monolithic_metal.pcm: Operation not permitted`. Run that
  model once from a normal Terminal, then `rater-cli bench` runs headless here
  (verified with `Models/Qwen3.5-4B-MLX-4bit`). `rate` remains the interactive
  path.
- Toolchain: Swift 6.4, `swift-tools-version: 6.0`, macOS 27 (Core AI's
  minimum), strict concurrency (`complete`).

## Product decisions

1. **Files plus a drawing page.** `rate` cycles a carousel of the passed image
   files and one black drawing page. The drawing page is the wrap point, so it
   sits at both ends of the carousel: leaving it clears the strokes, and Return
   submits it as an image. See `CLI/README.md` and `Core/Import/README.md`.
2. **One review window.** The CLI's window shows the input carousel, the
   submission beat, the working indicator, then the chosen automaton, in a
   single window with no split view. On submission the input separates into a
   double exposure — two copies a fraction of its height apart — then collapses
   onto the dot the collapse intro starts from, rejoining the copies as it
   shrinks them. The intro runs while the model works and ends on the horizon
   line; if the model outlasts it, the window holds the line until the choice
   is known. The automaton is one mirrored pair: two branches grow away from
   that line, and a camera pulls back at the growth rate to keep the growth in
   view, starting from a close-up on the seed. Past the point where one cell is
   one display element the camera keeps pulling back by averaging a wider block
   of the history per cell and drawing that average as tone, so the whole growth
   stays in view at decreasing resolution instead of sliding out through the
   horizon. The indicator runs at 30 fps on a reduced drawable so it does not
   compete with inference for the GPU. See `CLI/README.md`.
3. **A new input stops both branches immediately** before the next run begins.
4. **Two inference backends behind one protocol.** `Core` holds the
   prompt-building, the answer parsing, and the dialogue bookkeeping; `Agent`
   runs MLX snapshots and `AgentCoreAI` runs exported Core AI bundles, both as
   `Core`'s `AgentSession`. The CLI selects one with `--engine`, so the same
   images and the same prompt can be timed on either runtime. There is no
   model-free fallback agent: the CLI always runs a model. See
   `Core/Agent/README.md`.
5. **Local models only.** The engines never download. The MLX backend loads a
   snapshot directory (`--model` or `RATER_MODEL_PATH`) through the
   directory-only `loadModelContainer`; the Core AI backend loads an exported
   bundle (`--aimodel` or `RATER_AIMODEL_PATH`). A run with no directory fails.
   See `Agent/README.md` and `AgentCoreAI/README.md`.
6. **The review window's automaton runs on the GPU end to end.** The CPU sets
   the run's parameters; the board, the viewport clip, and the draw all stay on
   the GPU with no cell data read back to the CPU. The simulated board is much
   wider than the window, and the view renders only the viewport. See
   `Core/Render/README.md` for the pipeline and its barriers.

## Concurrency (repo-wide)

- Swift 6 strict. `Core` is `nonisolated` by default; `rater-cli`'s window
  code is `MainActor`. New Metal work must be confined to a dedicated
  `RenderActor` on its own run loop (see `Core/Render/README.md`).
- Never block the main thread. Model load, image decode/export, and all GPU
  work run off-main; the main thread receives finished values.

## Style

- Comments explain *why*, not *what*, and never restate the item they sit on.
  Cite the inventory when a constant or rule comes from there.
- Prefer descriptive names. A single letter is fine only where a tight scope
  makes it unambiguous (a loop index, a color channel).
- Keep additions small and tested.

## README documentation policy

The code is the primary documentation. A README in the chain is read before
the code beneath it, so every sentence must earn that place:

- **Guidance** — conventions and patterns to follow, pitfalls, and non-obvious
  decisions whose reason the code cannot show.
- **Remaining work** — unfixed bugs and dead-end investigations for issues not
  yet fixed, so future sessions do not repeat them.

A README never restates what the code shows (architecture essays, field lists,
call flows, a directory tree the file tree already shows, or status lists of
what works), and never documents history or completed fixes. Operational test:
if deleting a sentence leaves the README no less useful for the next task, the
sentence did not earn its place.

## General engineering rules

- No `static` or atomics when a local variable or parameter will do. They are
  for genuinely cross-thread shared state only.
- Never assume a test failure is pre-existing. Every failure is a regression
  until proven otherwise; establish the baseline from committed code, not a
  guess.
- Test and document workflows, not appearance. Pin counts, parsers, GPU
  mapping, determinism, and the contracts other code consumes (the frame the
  reveal takes over from, the retraction reaching the renderer). Do not test or
  document colors, shapes, gradients, edge softness, timing curves, animation
  phases, or exact frames: the user accepts the visual result by inspection,
  and tests or prose that pin the look only go stale.
- Document only verified facts, in neutral factual language. Do not speculate
  about causes or fixes; state what was observed, what was tried, and what was
  ruled out.
- Never silently discard an error: no bare `try?` for a fallible operation
  whose failure matters, and no `let _ =` to silence a result. Log or propagate
  it. `try?` is allowed only when the missing value carries no diagnostic
  value.
- Name files by domain concept; no `Utils.swift` / `Helpers.swift` catch-alls.
- Remove unused bindings; never silence a warning with `_`-prefixed names or
  `let _ =`.
- Describe code as it is now. Never refer to an earlier design, a state that
  never existed, or a change not present in the repository: no "previously",
  "no longer", "now uses X instead of Y", no counterfactual ("would
  otherwise…"), and no justification by what the code does not do. Name an
  entity as it is at the point of the code, and state what changed concretely
  or what the current state is — never an alternative that was never taken.
  Operational test: if deleting the clause leaves the sentence complete and
  accurate, it only contrasted with history.
- Every `unsafe` block and every unchecked claim (`withUnsafe…` access that
  reads or writes raw memory, `@unchecked Sendable`, `unsafeBitCast`) states
  the precondition it relies on in a `// SAFETY:` comment, and asserts that
  precondition when the check is O(1). An unchecked claim that cannot be
  justified in writing is a bug.
- Avoid `!` force-unwraps and `try!`: they are unhandled failures. Propagate
  with `try`, or handle the missing case. Force only behind an invariant
  proven at that point, and name the invariant. Test code may force after an
  explicit check such as `XCTUnwrap`.
- Remove development-time tracing and temporary debug output when the work
  lands; keep only instrumentation that serves ongoing diagnosis.
- Edit source with targeted edits, not scripts or bulk renames. A scripted
  rewrite hides intent, breaks blame and review, and drifts from the code
  around it.
- `grep`/`find` only within the repository and only narrowly; never walk large
  system directories (`~/Library`, caches, `.build`, `/tmp` clones). Read
  large compiler/test logs with the `read` tool or a single narrow `grep`;
  never loop over an entire compiler log.
- Avoid `sleep` longer than a few seconds in a shell command; run the real
  command with a tool timeout instead.

## End-of-task flow

1. Build and test: `swift build --disable-sandbox -c release` and `swift test
   --disable-sandbox`; fix warnings and failures.
2. Double-check the work for completeness and accuracy. Search the whole repo,
   not only the files you touched, for dangling references to anything you
   removed or renamed; confirm every call site, test, and doc is updated;
   re-read `git diff HEAD` for stray debug code and for wording that refers to
   an earlier design or a state that never existed; and confirm each claimed
   workflow has a call site and a test. Visual changes are accepted by
   inspection. State what you verified.
3. Apply the README deletion test to every subtree touched.
4. Record general lessons. When the session surfaced a general rule (a
   pitfall, a convention, a repeated mistake), add it to the README that owns
   that subtree, or here if it is repo-wide — once, at the level the placement
   invariant dictates, with an operational test.
5. Review the work against Rule Number One (actions relate to a coding task in
   this repository).
6. Suggest a commit message for `git diff HEAD` (run `git diff --stat HEAD`
   and read `git diff HEAD` first). Never include a `Signed-off-by` trailer;
   it is added automatically.

## Reference sources

- Inventory and rubric: `artifacts/`.
- `uni03C0` window conventions: clone at `/tmp/uni03C0`.
- `mlx-swift-lm` API: clone at `/tmp/mlx-swift-lm`. Verify API against the
  cloned source; never from memory.
- Core AI API and the exporter: clone `apple/coreai-models` at
  `/tmp/coreai-models`. The pinned revision is in `Package.swift`; verify API
  and bundle layout against that checkout, never from memory.
