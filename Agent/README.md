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
  model does not spend tokens on a reasoning preamble before its `class:` line.
- The container and the system-prompt KV cache are built once and shared; a
  failed build is retried on the next run. Both run off the main actor.
  `AgentEngine.prepare()` starts them so the first run pays only the user turn;
  it is best-effort, since the run retries and reports the error. `rate` then
  calls `AgentEngine.warmImage()`: one image turn at up to 256 px and one
  generated token, so the vision encoder and decode kernels are compiled before
  the first submission. It is best-effort and does not touch the choice history.

## Run

`AgentEngine.perform` uses the shared container and a system-prompt KV cache.
The cache is prefilled once from the chat template's system prefix; each run
copies it, prepares the user turn, and calls `generate(input:cache:state:)`, so
only the input is prefilled. The template is rendered once with a sentinel user
turn to isolate that prefix: the sentinel turn is a suffix of the render, and
subtracting it leaves the system tokens. A snapshot whose template cannot
isolate the prefix fails with `AgentEngineError.noCacheableSystemPrefix`.

There is no tool dispatch and no tool-dispatch round. The engine emits the whole
answer as `.text`, one `.metrics` event (prefilled and cached prompt tokens,
generation tokens, and times), then the parsed `.choice`, or `.failed` when no
usable catalog id appears; the parser is `Core/Agent`'s `ChoiceParser`. There is
no repair pass, so a miss costs one generation and a terse reason is accepted as
written.

## Remaining work

- Model choice is a heuristic, not settled. `classify artifacts/` scores
  class agreement alone (no exclusion list); `bench` exercises the no-repeat
  dialogue. With the current prompt `Qwen3.5-4B-MLX-4bit` scored 13/14 in
  `classify`, and both nesting drawings (`example_4.png`, `example_13.png`)
  were classed correctly in every run of both commands; a prompt whose
  `nesting` description required contained copies scored 12/14 and read
  `example_4.png` as `repetition` in every run. An occasional mis-rating is
  accepted (see `AGENTS.md`), so score the set rather than single drawings.
  In the no-repeat dialogue the 4B produced 10–12 usable answers out of 14 in
  three runs, and the same failures occur with and without the nesting change:
  they cluster on the randomness drawings after it chooses `T177`, which the
  exclusion note did not overturn. That note is the weak point to address next.
  A 14-image run costs 4.4–7.4 s per image, with 4,616–4,672 prompt tokens over
  26–43 s and 929–994 generated tokens over 31–41 s at 512 px.
  `Qwen3.5-2B-6bit` fails to name a usable id once the exclusion list is
  present; `gemma-4-e2b-it-4bit` is larger and weaker. `Qwen3.5-9B-4bit` matched
  12/14 in `bench` at 6.0–14.8 s per image (prompt 4,616 tokens / 61 s,
  generation 963 tokens / 65 s), with reason sentences as specific as the 4B's
  and a run that grows slower toward the end of the batch. Those 9B numbers
  predate the current `nesting` boundary, so re-measure it with
  `classify artifacts/` before preferring it; the 4B remains the faster product
  model.
- Image-only turns and the four-line `class:`/`id:`/`reason:`/`reason_zh:`
  answer work on the local snapshots. The mixture rubric's soft boundary is a
  wholly ordered, recognizable figure versus a picture that mixes order and
  randomness. The expected class of every reference drawing is in
  `artifacts/README.md`; score
  the set with `rater-cli classify artifacts/`.
- `AgentEngine` is not covered by `CoreTests`; test answer parsing in `Core`
  against `ChoiceParser` and test the model through the headless
  `rater-cli bench` (or the interactive `rater-cli rate`).
- The system-prefix cache lives for one `AgentEngine`, so each process pays its
  prefill once. Persisting it across processes would remove that cost.
