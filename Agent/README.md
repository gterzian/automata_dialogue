# Agent

The MLX VLM that implements `Core`'s `AgentRunning`. This is the only target
that links `mlx-swift-lm`, `swift-huggingface`, and `swift-transformers`;
everything the tests need lives in `Core/Agent` (see its README for the
per-input model, the answer parsing, and the prompt).

## Bridges

`mlx-swift-lm` ships a macro that generates the `TokenizerLoader` bridge from
`swift-transformers`. This target writes the conformance out by hand in
`HuggingFaceBridges.swift` instead: it pins the exact API surface this target
relies on and keeps the build independent of the macro plugin. When bumping
`swift-transformers`, re-check the one API point the bridge pins:
`AutoTokenizer.from(modelFolder:)`.

## Model

- **Local snapshots only.** The engine loads a directory
  (`Configuration.modelDirectory`, set by `rater-cli rate --model <dir>` or
  `RATER_MODEL_PATH`) through `loadModelContainer(from:using:)`, the overload
  that takes no `Downloader`, so it has no path to the network. A configuration
  with no directory fails the run with `AgentEngineError.noModelDirectory`;
  nothing is ever fetched. Obtain the snapshot outside the software.
  `Models/README.md` records the verified snapshots.
- `Models/Qwen3.5-4B-MLX-4bit` is the recommended snapshot: the smallest that
  both matches the class and honours the no-repeat list. The 9B is slower and
  the 2B fails the exclusion list (see Remaining work). A registry entry is not
  required: the config's `qwen3_5` model type loads it.
- The directory must be a complete Hugging Face snapshot (`config.json`,
  `*.safetensors` with `model.safetensors.index.json`, `tokenizer.json`,
  `tokenizer_config.json`, `vocab.json`, `chat_template.jinja`, and the
  preprocessor JSONs); the tokenizer's `eos_token` (`<|im_end|>`) supplies the
  stop token.
- Thinking is off (`additionalContext: ["enable_thinking": false]`), so the
  model does not spend tokens on a reasoning preamble before its `id:` line.
- The container is loaded once and shared; a failed load is retried on the next
  run. Load runs off the main actor.

## Run

`AgentEngine.perform` loads the shared container, builds a fresh `ChatSession`
with the immutable system prompt, thinking off, and the tool list omitted, then
calls `respond(to:image:)` once. There is no tool dispatch and no second
generation round. It emits the whole answer as `.text`, then the parsed
`.choice`, or `.failed` when no catalog id appears; the parser is
`Core/Agent`'s `ChoiceParser`. If the first answer names no catalog id, the
engine appends a correction and asks once more (the session still holds the
image); only a second miss fails the run.

## Remaining work

- Model choice is a heuristic, not settled. On the six `artifacts/example_*.png`
  with the no-repeat window, `Qwen3.5-4B-MLX-4bit` was the smallest model that
  held up (6/6 then 5/6, six distinct ids). `Qwen3.5-2B-6bit` is smaller but
  fails to name a usable id once the exclusion list is present;
  `gemma-4-e2b-it-4bit` is larger and weaker; `Qwen3.5-9B-4bit` is accurate but
  too slow. Re-check when the prompt or an example changes.
- Image-only turns and the two-line `id:`/`reason:` answer work on the local
  snapshots. The soft class boundary is a dense composition of many different
  shapes, which some models read as nesting rather than complexity.
- `AgentEngine` is not covered by `CoreTests`; test answer parsing in `Core`
  against `ChoiceParser` and test the model only through `rater-cli rate`.
