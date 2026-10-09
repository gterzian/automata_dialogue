# Agent

The MLX VLM that implements `Core`'s `AgentRunning`. This is the only target
that links `mlx-swift-lm`, `swift-huggingface`, and `swift-transformers`;
everything the dispatcher and tests need lives in `Core/Agent` (see its
README for the per-input model, tool order, and validation).

## Bridges

`mlx-swift-lm` ships `MLXHuggingFace` macros that generate the `Downloader` and
`TokenizerLoader` bridges from the Hugging Face packages. This target writes the
two conformances out by hand in `HuggingFaceBridges.swift` instead: it pins the
exact API surface this target relies on and keeps the build independent of the
macro plugin. When bumping `swift-huggingface` or `swift-transformers`, re-check
the two API points the bridges pin:
`HubClient.downloadSnapshot(of:revision:matching:progressHandler:)` and
`AutoTokenizer.from(modelFolder:)`.

## Model

- Default `mlx-community/Qwen3.5-9B-4bit`; `Qwen3.5-4B-4bit` is the 16 GB
  fallback (`Configuration.defaultModelID` / `fallbackModelID`). A registry
  entry is not required: `ModelConfiguration(id:)` plus the `qwen3_5` model
  type supplies the `.qwen35` tool-call format. The default download is pinned
  to a snapshot commit (`Configuration.pinnedRevision(for:)`);
  `Models/README.md` records it and the verified weight hashes.
- Thinking is off (`additionalContext: ["enable_thinking": false]`), so the
  model does not spend tokens on a reasoning preamble before the tool calls.
- The container is loaded once and shared; a failed load is retried on the next
  run. Download and load run off the main actor.
- **Local snapshots.** `Configuration.modelDirectory`, `rater-cli rate --model
  <dir>`, and `RATER_MODEL_PATH` all load from a directory instead of the hub.
  `loadModelContainer` never calls the downloader for a `.directory`
  configuration, so no network is touched. The directory must be a full Hugging
  Face snapshot (`config.json`, `*.safetensors` with
  `model.safetensors.index.json`, `tokenizer.json`, `tokenizer_config.json`,
  `vocab.json`, `chat_template.jinja`, and the preprocessor JSONs). Download it
  once, e.g. `huggingface-cli download mlx-community/Qwen3.5-9B-4bit --local-dir
  <dir>`; the tokenizer's `eos_token` (`<|im_end|>`) supplies the stop token.

## Ordering

The engine buffers assistant text and emits it only after the stream ends, so
the transcript always sees the rating card, then the choice card, then the
closing sentence even if the model writes text before its tool calls. A run that
exceeds the dispatcher's call limit ends silently because the dispatcher already
emitted `.failed`.

## Remaining work

- The engine compiles and links with `RATER_AGENT=1`, but has not been run
  against real weights yet. First real run should confirm open decisions
  §11.1–§11.3: model choice, image-only turns (empty prompt), and the
  `qwen3_5` tool-call recovery path.
- `AgentEngine` is not covered by `CoreTests`; keep run-level tests in `Core`
  against `ToolDispatcher` and test the model only through `rater-cli rate`.
