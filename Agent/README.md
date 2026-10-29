# Agent

The MLX backend that implements `Core`'s `AgentSession`. It is the only target
that links `mlx-swift-lm`, `swift-huggingface`, and `swift-transformers`; the
Core AI backend is `AgentCoreAI`, and the per-input model, the prompt, the
answer parsing, and the dialogue both backends share are in `Core/Agent` (see
its README).

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
  it is best-effort, since the run retries and reports the error.

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

- Model choice is a heuristic, not settled. On the `artifacts/example_*.png`
  reference set with the no-repeat window, `Qwen3.5-4B-MLX-4bit` chose 13–14
  distinct ids in 13–14/14 submissions at 3.2–5.2 s per submission after the
  one-time system-prefix prefill (~9 s; the whole 14-image `bench` takes
  59–71 s). Class agreement is approximate: the dialogue treats the class the
  model commits to as the answer, and an occasional mis-rating is accepted.
  `Qwen3.5-2B-6bit` is smaller but fails to name a usable id once the exclusion
  list is present; `gemma-4-e2b-it-4bit` is larger and weaker. On the current
  prompt, `Qwen3.5-9B-4bit` was not better: it matched 10/14 classes in
  `classify` and 9/14 in the no-repeat dialogue, against the 4B's 11/14 and
  10/14, while its per-run prefill plus generation was about 1.7–2× the 4B's.
  The 4B remains the sweet spot. The prompt now asks for a fourth `reason_zh:`
  line, so the figures above no longer describe the current generation cost;
  re-run `classify artifacts/` and `bench artifacts/` before trusting them.
- Image-only turns and the four-line
  `class:`/`id:`/`reason:`/`reason_zh:` answer work on the local snapshots. The
  mixture rubric's soft boundary is a wholly ordered, recognizable figure versus
  a picture that mixes order and randomness. The expected class of every
  reference drawing is in `artifacts/README.md`; score the set with
  `rater-cli classify artifacts/`, whose last line is the class agreement.
- `AgentEngine` is not covered by `CoreTests`; test answer parsing in `Core`
  against `ChoiceParser` and test the model through the headless
  `rater-cli bench` (or the interactive `rater-cli rate`).
- The system-prefix cache lives for one `AgentEngine`, so each process pays its
  prefill once. Persisting it across processes would remove that cost.
