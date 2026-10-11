# AGENTS.md — Automata Rater

Automata Rater: a native macOS app where a local MLX agent chooses one of 106
curated cellular automata to display for an input. The design of record is the
draft design doc and the two artifacts in `artifacts/`.

## Product intent

The unit of the product is a **dialogue**, not a lookup. Each submission is the
user showing something; the app answers in the shared language of complexity by
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
prompt or model changes; see `Agent/README.md`.

## Rule Number One

Only perform an action that directly relates to a coding task in this
repository.

## Rule Number Two: Network

Never make network requests to external hosts without explicit prior approval.
Use local resources only. (`huggingface.co` is unreachable from the sandbox;
GitHub has been approved for cloning reference repositories into `/tmp`.)

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

## Build and test

- **`xcodebuild` does not work in this sandbox.** Do not rely on it. Build and
  test with SwiftPM:
  - `swift build --disable-sandbox -c release` — builds `Core`, `Agent`, and
    `rater-cli`. **Anything the user runs** (the app, `rater-cli`) is a release
    build, so the CLI is at `.build/release/rater-cli`.
  - `swift test --disable-sandbox` — runs the unit tests.
  SwiftPM's own sandbox cannot apply here, so the flag is required; plain
  `swift build`/`swift test` fail with `sandbox_apply: Operation not
  permitted` before compiling anything.
- To see only warnings from this repo's targets (the `Agent` dependency tree
  emits its own warnings from `.build/checkouts`):
  `swift build --disable-sandbox -c release 2>&1 | grep warning: | grep -v .build/checkouts`.
- The `Agent` target links `mlx-swift-lm` and a large C++/Metal build, so every
  SwiftPM command builds it. It needs Xcode's Metal toolchain component
  (`xcodebuild -downloadComponent MetalToolchain`); without it the `metal`
  shim has no compiler and `Cmlx` fails. If the link instead fails with
  undefined `_mlx_*` symbols, the `mlx-swift` checkout's `mlx-c` submodule is
  empty; populate it once with `git -C .build/checkouts/mlx-swift submodule
  update --init Source/Cmlx/mlx-c`.
- **Running the model does not work inside the agent sandbox.** MLX
  JIT-compiles some Metal kernels at runtime, and the Metal frontend's module
  cache (`/var/folders/…/C/com.apple.metalfe`) is not writable here, so the
  process traps with `Unable to build metal library from source … Operation not
  permitted`. Build and `swift test` work; run `rater-cli rate` from a normal
  Terminal.
- The Xcode project (`project.yml`, generated by `xcodegen`) is kept in sync
  for the eventual `.app`, but is not the iteration path here.
- Toolchain: Swift 6.4, `swift-tools-version: 6.0`, macOS 26, strict
  concurrency (`complete`).

## Product decisions (deviations from the design doc)

1. **No in-app drawing.** The user drags an existing image file onto the input.
   The drawing popover/canvas of the design doc is dropped; see
   `Core/Import/README.md`.
2. **Single panel.** One panel shows the running automaton; the choice card and
   the input occupy the same panel. No split view, no session tabs in v1. See
   `Client/README.md`.
3. **A new prompt stops the running automaton immediately** before the new run
   begins.
4. The MLX VLM is isolated in an `Agent` target so `Core` stays pure and
   testable; `Core` holds the prompt-building and answer-parsing logic. There is
   no model-free fallback agent: the app always runs the model. See
   `Core/Agent/README.md`.
5. **Local models only.** The engine never downloads. It loads a snapshot
   directory (`--model` or `RATER_MODEL_PATH`) through the directory-only
   `loadModelContainer`, and a run with no directory fails. See
   `Agent/README.md`.

## Concurrency (repo-wide)

- Swift 6 strict. `Core` is `nonisolated` by default; `Client` is `MainActor`
  by default. New Metal work must be confined to a dedicated `RenderActor` on
  its own run loop; today `MetalAutomaton` runs synchronously on the caller
  (remaining work — see `Core/Render/README.md`).
- Never block the main thread. Model load, image decode/export, hashing, and
  all GPU work run off-main; the main thread receives finished values.

## Style

- Comments explain *why*, not *what*. Cite the inventory or design section when
  a constant or rule comes from there.
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
- Document only verified facts. Do not speculate about causes or fixes; state
  what was observed, what was tried, and what was ruled out.
- Never silently discard an error: no bare `try?` for a fallible operation
  whose failure matters, and no `let _ =` to silence a result. Log or propagate
  it. `try?` is allowed only when the missing value carries no diagnostic
  value.
- Name files by domain concept; no `Utils.swift` / `Helpers.swift` catch-alls.
- Remove unused bindings; never silence a warning with `_`-prefixed names or
  `let _ =`.
- Describe code as it is now. No migration or design-history narration; a
  comment earns its place by carrying a reason the code cannot show, not by
  paraphrasing the code around it.
- `grep`/`find` only within the repository and only narrowly; never walk large
  system directories (`~/Library`, caches, `.build`, `/tmp` clones). Read
  large compiler/test logs with the `read` tool or a single narrow `grep`;
  never loop over an entire compiler log.
- Avoid `sleep` longer than a few seconds in a shell command; run the real
  command with a tool timeout instead.

## End-of-task flow

1. Build and test: `swift build --disable-sandbox -c release` and `swift test
   --disable-sandbox`; fix warnings and failures.
2. Apply the README deletion test to every subtree touched.
3. Review the work against Rule Number One (actions relate to a coding task in
   this repository).
4. If asked for a commit message, propose one for `git diff HEAD`. Never
   include a `Signed-off-by` trailer; it is added automatically.

## Reference sources

- Inventory and rubric: `artifacts/`.
- `uni03C0` conventions (transcript store, glass chrome, window): clone at
  `/tmp/uni03C0`.
- `mlx-swift-lm` API: clone at `/tmp/mlx-swift-lm`. Verify API against the
  cloned source; never from memory.
