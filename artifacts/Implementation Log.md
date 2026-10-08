# Automata Rater — Implementation Log & Design Guidance

This file is the running record for the build. It has two parts:

1. **Working notes** — environment, deviations, status, and what is next.
2. **Design intent & guidance** — the durable intent from the retired draft
   v0.4 design doc. It is deliberately *not* a restatement of the code: it
   carries the intent, the non-obvious decisions, the open questions, and the
   design of what is not built yet. For anything built, the code and the
   per-directory `README.md` chain are the source of truth.

Companion artifacts: `Curated Inventory of Cellular Automata.md` (the 32
entries and their CPU `Program` source) and `System prompt_ rating inputs as
simple, structured, random, or complex.md` (the rubric). `AGENTS.md` and the
README chain carry the engineering rules.

---

## Part 1 — Working notes

### Deviations from the design doc (user-directed)

1. **No drawing popover.** Drawings are not created in-app. The user drags an
   existing image file onto the input; the file is attached to the prompt and
   sent to the agent. `SmoothedStroke` / `DrawingCanvasView` /
   `DrawingPopoverController` are dropped. `Core/Import` replaces
   `Core/Drawing` (attachment + PNG normalization to 512×512).
2. **Single panel, not a two-panel session window.** The window shows one
   panel. While an automaton is running, the panel shows the automaton. The
   input sits at the bottom. There is no split view and no separate history
   column; the transcript/rating/choice cards render in the same panel as a
   lightweight overlay/history strip.
3. **A new prompt immediately stops the running automaton.** Sending a new
   input cancels/stops the current render before the new run starts.

### Environment findings

- macOS 26.7.1, Xcode 27.0, Swift 6.4, xcodegen present. MTL4 headers are in
  the MacOSX27.0 SDK (`MTL4*.h`), so the Metal 4 render path is buildable.
- GitHub reachable (cloned `ml-explore/mlx-swift-lm` 3.32.3,
  `huggingface/swift-huggingface` 0.13.0, `huggingface/swift-transformers`
  1.3.4). **huggingface.co is now reachable**; the API serves
  `mlx-community/Qwen3.5-9B-4bit` and `Qwen3.5-4B-4bit`.
- **The Metal toolchain component is installed** (user-installed; `xcodebuild
  -showComponent MetalToolchain` reports `Status: installed`, metalfe
  32023.921). `RATER_AGENT=1 swift build --disable-sandbox` now builds
  `mlx-swift` and the `Agent` target cleanly (only an unrelated SwiftPM warning
  about the `mlx-swift_Cmlx.bundle` creator). No model weights are present yet.
- **MLX runtime deps resolved and pinned** in `Package.resolved`:
  `mlx-swift-lm` 3.32.3, `mlx-swift` 0.32.3, `swift-huggingface` 0.13.0,
  `swift-transformers` 1.3.4, `swift-syntax` 603.0.2.
- Reference clones used for API fidelity: `/tmp/uni03C0`,
  `/tmp/mlx-swift-lm`, `/tmp/swift-huggingface`, `/tmp/swift-transformers`.
- **`xcodebuild` does not work in this sandbox.** Build and test with
  `swift build --disable-sandbox` and `swift test --disable-sandbox`; plain
  `swift` fails with `sandbox_apply: Operation not permitted` because SwiftPM's
  own sandbox cannot apply here. The SwiftUI macro plugin
  (`swift-plugin-server`) is blocked the same way, so the `Client` target
  cannot be fully type-checked here; verify with `./run.sh` where `xcodebuild`
  works.

### Status

Legend: [x] done / verified, [~] partial, [ ] pending.

- [x] **P0 scaffold** — `project.yml` (Core framework, Client app, CoreTests,
  rater-cli), `run.sh`, `.gitignore`, `Package.swift`, `AGENTS.md` + README
  chain.
- [x] **P1 catalog + CPU programs** — `ProgramSpec`/`GPUProgram`/`Behavior`/
  `Board`/`DisplayHints`/`Palette`, all 32 entries, `SplitMix64`,
  `ElementaryCA`, `TotalisticCA`, `RowHash`. Golden row hashes for all 32.
  Note: E90/E22 and E150/E105 coincide at even steps — a real property of the
  rules (documented in `ProgramTests`).
- [x] **P2 agent logic (pure)** — `Rating`, `Choice`, `AgentEvent`,
  `AgentInput`, `ToolInvocation`, `ToolSchemas`, `ToolDispatcher` actor,
  `SystemPrompt`, `HeuristicAgent`.
- [x] **P3 import** — `ImageAttachment`, `ImageImport.normalize` (aspect-fit
  to a 512×512 PNG), temp-folder layout and purge.
- [x] **P4 session** — `TranscriptEntry`, `TranscriptStore` (append-only JSONL,
  `apply(AgentEvent)`), `StreamingRefreshGate`, `HeightCache`.
- [x] **P5 render** — `ColorGrid`, `Fit`, `CPUAutomatonRenderer`,
  `IncrementalRenderer`, `ShaderSource`, `GPUContext`, `MetalAutomaton`.
  A GPU-vs-CPU readback test passes on this machine. Renders verified visually
  (`rater-cli render`): E90 Sierpinski, E110 one-sided growth, T1329 column,
  T177 random, T1599 long transient.
- [x] **P5b render seam** — `MetalSimulation` (incremental GPU step, fits only
  newly-ready rows), `RenderExecutor` (dedicated run-loop `SerialExecutor`),
  `RenderActor` (confines Metal to that thread and delivers `RenderFrame`s),
  `FrameSink`/`FrameClock`/`ReadbackSink`/`SinkFactory`, and the three frame
  slots.
- [x] **P5c layer sink** — `DisplayLinkClock` (`CAMetalDisplayLink`, latency 2),
  `LayerSink` (presents the latest frame), `LayerRenderer` (`runs` span
  compaction, GPU-built indirect draw args, instanced-quad render pass), and
  `RenderActor.drive`. Offscreen tests compare the span compaction with a CPU
  run-length pass and read back the render.
- [x] **P5d pacing + GPU-resident frames** — `RenderPacing` (`.fixed`/`.timed`,
  `Δ × stepsPerSecond` clamped per tick), `GPUColorGrid`,
  `FrameSink.wantsGPUResidentFrames`, `MetalSimulation.renderGPU`, the
  incremental `LayerRenderer.render(gpu:)` path that appends only new rows to
  the accumulated spans, and `RenderActor.makeLayerSink(layer:)` (the sink and
  simulation share one context). Remaining: app wiring, `LEDSink`; see
  `Core/Render/README.md`.
- [x] **P6 app (single panel)** — `ClientApp`, `ContentView` (automaton panel,
  transcript strip, drag-and-drop input bar), `AutomatonView`/
  `AutomatonNSView`, `RaterModel` (agent run + ~30 Hz `IncrementalRenderer`
  animation; a new prompt stops the running automaton). Type-checks against
  `Core` except for the blocked SwiftUI `@State` macro.
- [x] **P7 CLI** — `catalog`, `hashes`, `cells`, `render <id>`/`--all`, `gpu`
  (Metal-vs-CPU check), and `rate <path>...` (runs the agent per image and
  prints label/id/latency) done.
- [x] **P8 Agent target** — `Agent/AgentEngine.swift` (`AgentRunning` over
  `ChatSession` + `ToolDispatcher`, per-run session, thinking off, buffered
  closing sentence, download *or* local-snapshot loading),
  `Agent/HuggingFaceBridges.swift` (hand-written `Downloader` and
  `TokenizerLoader` bridges for `swift-huggingface`/`swift-transformers`), and
  dependencies in `project.yml` (always) and `Package.swift` (`RATER_AGENT=1`).
  A local snapshot comes from `Configuration.modelDirectory`,
  `rater-cli rate --model <dir>`, or `RATER_MODEL_PATH`; no downloader is
  invoked for a `.directory` configuration. Compiles and links with
  `RATER_AGENT=1`; the real-model run is pending weights.

Test count: **76 tests, 0 failures** (`swift test --disable-sandbox`),
including the Metal 4 readback comparison, the GPU incremental-vs-`IncrementalRenderer`
parity test, the layer span/render tests, the incremental span-accumulation
test, timed pacing, and the run-loop render actor.

### Metal 4 / layer findings (also in `Core/Render/README.md`)

- **The argument table is live at GPU execution time.** Rebinding one table's
  addresses between encoded dispatches makes every dispatch resolve to the
  final address. The step kernels therefore read the current row from a
  GPU-side `head` counter advanced by a 1-thread `bump_head` kernel, so all
  argument tables keep constant bindings (the design's §11.9 fallback).
- **`CFRunLoopRun()` returns immediately when the run loop has no sources.**
  It killed the `RenderExecutor` thread before the first job, hanging every
  `await` on `RenderActor`; the run loop now holds an empty `CFRunLoopSource`.
- **Compute-to-render ordering is explicit:** the compute encoder publishes
  spans with `barrier(afterStages: .dispatch, beforeQueueStages: .vertex,
  visibilityOptions: .device)` before the render encoder reads them.
- **Incremental span accumulation.** A display row never changes once fitted,
  so the GPU-resident path appends only the rows a frame adds to the existing
  spans; the counter persists across frames and `LayerUniforms.rowOffset`
  places the new rows. A frame whose first row is 0 starts a run and resets the
  counter. The spans buffer is sized for every cell, so the accumulated count
  stays in bounds.
- Render API names: `command.makeRenderCommandEncoder(descriptor:)`,
  `compiler.makeRenderPipelineState(descriptor:)`,
  `render.setArgumentTable(_:stages:)`,
  `render.drawPrimitives(primitiveType:indirectBuffer:)`; `MTL4RenderPassDescriptor`'s
  colour-attachment subscript is optional; `CAMetalLayer.residencySet` is added
  to the queue. This SDK's `MTLDrawable` has no
  `waitForDrawable`/`signalDrawable`; the display link's update supplies the
  drawable and plain `present()` submits it.
- Swift API names: `device.makeMTL4CommandQueue()`, `device.makeCompiler`,
  `device.makeResidencySet`, `compiler.makeLibrary/makeComputePipelineState`,
  `command.makeComputeCommandEncoder()`, `setAddress(_:index:)`,
  `dispatchThreads(threadsPerGrid:threadsPerThreadgroup:)`.
- The kernels compile from a source string (`ShaderSource.simulation`) because
  SwiftPM cannot build a `.metallib`.

### What is next

1. Put a Qwen3.5 snapshot on disk and run `rater-cli rate` (or the app) with
   `RATER_MODEL_PATH`/`--model`, over the rubric's calibration anchors. Settle
   open decisions §11.1–§11.3 (model choice, image-only turns, the `qwen3_5`
   tool-call recovery path).
2. `Core/Render` seam: the compute, actor, layer sink, Δ-based pacing, and
   GPU-resident frames landed (P5b–P5d). Remaining: wire `RaterModel` to a host
   `CAMetalLayer` + `LayerSink` + `RenderActor.drive` (the sink now comes from
   `makeLayerSink(layer:)`), then `LEDSink` once its hardware is known.
3. Catalog review after a real evaluation run: the rating→inventory mapping
   (§11.5) and any `look`/`Behavior` adjustments.

---

## Part 2 — Design intent & guidance

The retired design doc expressed an intent; the sections below keep that intent
and the decisions a future session cannot recover from the code. Where code and
this text disagree, the code wins for behavior already built; this text wins for
intent and for anything not built yet.

### 1. Product intent

- One app: an input is rated **simple / structured / random / complex** and
  matched to one of 32 curated automata whose *look* fits; the automaton is
  shown live. Flow: attach an image (drag-and-drop) → normalize to 512×512 →
  send → the agent rates, then chooses → the panel renders the entry.
- The rating is a judgment about the input's **structure**, not its subject:
  a few primitives (simple), a short generating rule (structured), no
  compressible rule (random), or simple primitives producing emergent
  structure (complex). The four labels map to four inventory classes, which is
  intentionally coarse so the model has a small, reliable choice.
- The two tool calls are ordered (rate, then choose) because the rating must be
  visible before the choice and the UI depends on that order.

### 2. Architecture guidance

- **`Core` stays AppKit-free and dependency-free** so it is testable and the
  render core is headless. Anything needing a view or an `NSView`-backed layer
  goes in `Client`.
- `Client` is the only AppKit/SwiftUI target; the MLX VLM belongs in a separate
  `Agent` target that depends on `Core` (the design's fallback if MLX cannot be
  embedded in the `Core` framework — §11.6).
- Concurrency: `Core` nonisolated, `Client` MainActor, and new Metal work
  confined to a `RenderActor` (see §5). This is the repo-wide rule in
  `AGENTS.md`.

### 3. Agent guidance

- **Per-input context, not accumulating history.** Each run is one self
  contained turn (system prompt + this input + the tool exchange); the panel
  shows the full history but the model does not see it. Intent: constant
  latency and an identical, cacheable system-prompt prefix. Keep it unless
  there is a product reason to give the model memory.
- **Invariants that must not regress.** The user-visible order (rating card,
  then choice card) is identical on every run whatever the model does. The
  dispatcher **never throws** — a throw from the tool closure ends the stream —
  so every validation outcome is a returned corrective string. The sixth tool
  call without a choice fails the run. The `choose_automaton` id enum is
  generated from the catalog. Details and messages: `ToolDispatcher.swift`.
- **Model constraints.** `Qwen3.5-9B-4bit` default, 4B fallback for 16 GB;
  thinking disabled; temperature 0.2; the image is 512×512. Rationale: local,
  small, vision-capable of the rating task.
- **Rubric edits are intentional**: fields framed as `rate_input` inputs, no
  multi-input summary, no continuation/disagreement style lines. Every
  submission is a new input to rate.
- **Prompt cache** is a later optimization; if adopted, the cold system-prompt
  prefix is the thing to cache (routes in `ChatSession`).
- Not built: `AgentEngine` (MLX), `rater-cli rate`. Open questions §11.1–§11.5.

### 4. Catalog guidance

- **One table, three consumers.** `ProgramSpec` drives the renderer, the prompt
  index, and the tool-schema enum. Never hand-maintain a generated list; a test
  asserts the three agree. Add an entry by adding one `ProgramSpec` and
  refreshing goldens (`rater-cli hashes`).
- `look` is the **matching text** the model sees; keep it to one sentence and
  derived from the inventory's *Look* paragraph.
- The rating→classes mapping lives on `RatingLabel.allowedBehaviors`. The
  intent is to widen it only if a real evaluation shows the current mapping
  mis-fits (§11.5).
- Behavior counts (9/11/6/6) and the inventory's widths/starts are fixed by the
  artifact; tests enforce them.

### 5. UI guidance (single panel — deviation 2)

- v1 intent: the automaton is the focus while running; the input is always
  available at the bottom; a new prompt stops the running automaton first.
- Transcript and prompt are built for long sessions: cost follows the visible
  rows, streaming text refreshes in 0.25 s batches (first chunk and settle are
  immediate), and unchanged rows are never re-measured. These rules are in
  `Core/Session/README.md`; keep new row kinds within them.
- Not built (design intent, in case the single panel grows back): session tabs
  in one window with stable entry ids, a windowed `NSTableView` coordinator,
  off-main height pre-measurement, follow-sticky tail, and AppKit glass chrome
  (`NSGlassEffectView`). The design's reason for each is the same as uni03C0's:
  scroll and streaming cost independent of history size.

### 6. Render guidance

- **Seam intent.** The simulation core is sink-independent (compute the grid);
  the sink owns delivery; the clock owns pacing. New GPU work goes behind
  `FrameSink`/`FrameClock`, not inside the core, so the screen, CPU readback,
  and LED paths share one compute implementation.
- **Why Metal 4 + macOS 26.** The design chose Metal 4 for the reusable command
  buffer/allocator model, explicit residency, and indirect-command presentation.
  Minimum macOS 26 follows from glass chrome plus Metal 4 (§11.7).
- **Dedicated render thread.** Metal objects, drawable acquisition, and
  `present` belong on a `RenderActor` on its own run loop (a `SerialExecutor`
  over `CFRunLoopPerformBlock`). The main thread only configures the layer and
  posts commands through a lock-guarded mailbox. This keeps present off the
  main thread and avoids Main Thread Checker issues.
- **Three frames in flight.** Three `CAMetalLayer` drawables mirror three frame
  slots so the CPU encodes N+1/N+2 while the GPU runs N (§11.8).
- **Fit.** Nearest for `k == 1`, majority for `k > 1`; a display column past the
  board reads background, never wrapped. The known caveat is that majority vote
  erases sparse single-cell features under downsampling; boards narrower than
  the panel upscale (`k == 1`), so only the 6101-wide dense entries downsample.
- **Metal 4 gotcha (important).** The argument table is read live at execution
  time, so per-dispatch address rebinds all resolve to the last value. Use a
  GPU-side `head` counter (as built: `bump_head`) or one table per dispatch.
- **Not built — design intent for the rest of the path:**
  - `RenderActor`/`RenderExecutor` + command mailbox (`.show`, `.replay`,
    `.setActive`, `.configure`, `.shutdown`).
  - `FrameSink`/`FrameClock` protocols, `ReadbackSink`, `SinkFactory`; three
    slots (allocator, reusable command buffer, buffers, per-slot sink
    resources); `history` is a ring, one row computed from the previous.
  - `LayerSink`: `DisplayLinkClock` over `CAMetalDisplayLink`
    (`preferredFrameLatency = 2`); geometry from the drawable's pixels; a `runs`
    kernel that compacts each non-background run into a `Span` (so draw cost
    follows the structure), an `encode` kernel that writes the
    `MTLIndirectCommandBufferExecutionRange` and the draw command on the GPU,
    and a render pass that clears to `palette[0]` and executes the ICB. Submit
    sequence: `waitForDrawable`, `commit` with a feedback handler that releases
    the slot, `signalDrawable`, plain `present()` (time-targeted present
    asserts under `CAMetalDisplayLink`). Add the layer's residency set.
  - `ReadbackSink`: read the shared `colorGrid` bytes in the feedback handler
    (verified complete here by the passing readback test).
  - `LEDSink` (flag `RATER_SINK_LED`, §11.13): geometry is the LED matrix with
    no upscale (one LED per cell), a `pack` kernel maps palette → panel color
    order, and an `LEDTransport` sends packed bytes.
- Vertex/fragment shaders for the layer sink and any future sink compile into
  the `Core` bundle's `default.metallib`; in this repo the compute kernels are a
  source string because SwiftPM cannot build a `.metallib`.

### 7. Performance guidance

Keep the three properties: (1) UI cost follows visible rows and streaming
batches; (2) after the one-time weight download everything is local; (3) render
ahead — a transcript buffer beyond the viewport and three encoded frames in
flight. New code must not move model load, image work, JSONL writes,
pre-measuring, or Metal onto the main thread.

### 8. Persistence guidance

- Transcript is append-only JSONL under Application Support; images live **only**
  under the temp session folder (never Application Support), because they are
  large and disposable. A session's temp folder is removed on close; stale
  folders are purged at launch. Restore open sessions lazily.
- A choice stores only the catalog id; the panel rebuilds from the catalog.
  Keep entries self-describing so a transcript can be replayed without the
  model.

### 9. Setup constraints

- Packages and versions (`mlx-swift-lm` 3.32.x etc.) are in `project.yml`; keep
  the pinned minors when touching MLX.
- `RATER_SINK_LAYER` is on by default; `RATER_SINK_LED` off. A sink's Swift and
  `.metal` files are included only under its flag.
- The app is unsandboxed in development (writes to Application Support and
  temp); a sandboxed build would need Outgoing Connections for the download.
- Build through `xcodebuild` with `-skipMacroValidation` for the Hugging Face
  macro; `run.sh` generates, builds, quits the running instance, and launches.

### 10. Testing guidance

- Unit tests carry no live model and no GPU requirement (Metal tests skip when
  `MTLCreateSystemDefaultDevice()` is not `.metal4`).
- The load-bearing tests are the invariants: catalog↔schema↔prompt agreement,
  dispatcher order/validation, CPU golden row hashes, and **GPU kernels equal
  the CPU reference** (the GPU is an optimization, never the source of truth).
- The real-model evaluation (`rater-cli rate`) is a manual run over reference
  drawings with expected labels from the rubric's calibration anchors (single
  line, glyphs, five bars, three scaled triangles, tangled polyline, balanced
  composition); run it when the prompt or model changes.

### 11. Open decisions (from the design's "decisions to confirm")

1. **Model.** 9B-4bit default, 4B fallback; latency on target machines decides.
2. **Image-only turns.** Confirm an empty prompt string works with Qwen3.5, or
   add a fixed neutral prompt.
3. **Qwen3.5 tool calls.** Verify recorded outputs through the `qwen3_5` parser
   and recovery under the default `ToolCallRecoveryPolicy`.
4. **Guided generation.** Decide whether `MLXGuidedGeneration` should constrain
   the label/id enums.
5. **Allowed ids per label.** Widen `RatingLabel.allowedBehaviors` only if the
   first evaluation run shows mis-fits.
6. **MLX inside `Core`.** Confirm the `mlx-swift_Cmlx` `default.metallib`
   resolves from the embedded framework; otherwise use the `Agent` target.
7. **Minimum macOS.** 26 (glass + Metal 4) — settled.
8. **"Three buffers".** Three drawables + three frame slots; if drawable
   contention appears, rotate three IOSurface-backed textures through a layer.
9. **Per-step constants.** Settled: the argument table is live, so the row
   index comes from the GPU-side `head` counter.
10. **ICB encoding in Metal 4.** The `encode` kernel builds the draw command on
    the GPU; fallback is a CPU-built indirect draw over the same spans.
11. **Layer residency.** Add `CAMetalLayer.residencySet` to the queue; confirmed
    property in the macOS 26 SDK, re-confirm at M2a.
12. **Skipped ticks and threading.** Confirm returning from `needsUpdate`
    without presenting is accepted and the executor's thread check passes.
13. **LED hardware.** Geometry, color order, wiring order, refresh rate, and
    wire protocol are chosen with the hardware; the seam fixes the pieces.
14. **CPU readback timing.** Confirmed by the passing readback test.
15. **Sink fan-out.** One sink per surface in v1; a list of sinks each with its
    own geometry and `fit` is the extension point.

### 12. Milestones (roadmap)

The original ordering was M1 (agent CLI) → M2a (render thread + presentation) →
M2b (automaton on the GPU) → M6 (LED sink) → M3 (window) → M4 (drawing) →
M5 (persistence/polish). In this repo P0–P5 delivered the catalog, agent logic,
import, session, and the CPU + Metal compute paths; P6 the single-panel app;
P7 the CLI; P5b the headless render seam; P5c the layer sink and display
clock. The larger milestones still to schedule are the **app wiring and
GPU-resident frames** (M2a/M2b remainder), the **MLX `AgentEngine` +
evaluation** (M1), **persistence wiring and sessions** (M5), and the **LED
sink** (M6).

### 13. References

- uni03C0 (AppKit glass chrome, transcript store, window) at
  `github.com/gterzian/uni03C0` — clone conventions from `/tmp/uni03C0`.
- `mlx-swift-lm` API (`ChatSession`, `ToolSpec`, `ToolCall`, `ToolCallPolicy`,
  `GenerateParameters`, `UserInput.Image`, `Chat.Message`,
  `ModelFactoryRegistry`, tool-call formats) — verify against `/tmp/mlx-swift-lm`,
  never from memory.
- Apple Metal 4 (`MTL4CommandQueue`, `MTL4CommandBuffer`, `MTL4CommandAllocator`,
  `MTL4ComputeCommandEncoder`, `MTL4RenderCommandEncoder`, `MTL4ArgumentTable`,
  `MTL4Compiler`, `MTLIndirectCommandBuffer`, `MTLResidencySet`) and QuartzCore
  `CAMetalDisplayLink`/`CAMetalLayer`.
- The design's source-verification table (checked 2026-10-06) is not retained
  here; items it marked "confirm" (§11.6, §11.8, §11.10–§11.12) are re-verified
  when the render seam and the `Agent` target land.
