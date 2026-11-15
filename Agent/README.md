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
  `../Models/README.md` records the verified snapshots.
- `../Models/Qwen3.5-9B-4bit` is the snapshot in use; the 4B is the faster
  alternative when latency matters more. A registry entry is not required: the
  config's `qwen3_5` model type loads all of them. Score a snapshot with
  `rater-cli classify artifacts/`; the prompt no longer lists the catalog, so
  the model is judged only on the class it names.
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
  calls `AgentEngine.warmImage()`: one image turn at the configured image size
  and sampling that generates three tokens, so the vision encoder runs at the
  first submission's patch count and the one-token decode step runs once.
  `rate` shows the intro, taking no input, until the warm-up finishes, then
  opens its first page. The warm-up is best-effort and does not touch the
  session's shown ids.

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
class appears; the parser is `Core/Agent`'s `RatedClassParser`. The `.choice`
carries the id `SessionChoices` picked from the rated class, the class itself,
and the two reasons. There is no repair pass, so a miss costs one generation and
a terse reason is accepted as written.

## Remaining work

- **The warm-up is not measured against the first submission.** It runs the
  review's image size, sampling, and an empty first prompt, but nothing here
  compares the first `rate` turn with the second; `rate`'s debug output prints
  each turn's prefill and generation seconds, so the residual excess is whatever
  the first image shows over the second.
- **Class accuracy is a heuristic, not settled.** `classify artifacts/` scores
  class agreement alone; `bench` exercises the session's random pick and its
  timing. An occasional mis-rating is accepted (see `AGENTS.md`), so score the
  set rather than single drawings. The first run of a snapshot must happen
  outside the sandbox, so its Metal kernels are cached (`AGENTS.md` → Build and
  test).
- Image-only turns and the three-line
  `class:`/`reason:`/`reason_zh:` answer are the format. The mixture rubric's
  soft boundary is a wholly ordered, recognizable figure versus a picture that
  mixes order and randomness. The expected class of every reference drawing is
  in `artifacts/README.md`; score the set with `rater-cli classify artifacts/`.
- `AgentEngine` is not covered by `CoreTests`; test answer parsing in `Core`
  against `RatedClassParser` and the session pick against `SessionChoices`, and
  test the model through the headless `rater-cli bench` (or the interactive
  `rater-cli rate`).
- The system-prefix cache lives for one `AgentEngine`, so each process pays its
  prefill once. Persisting it across processes would remove that cost.
