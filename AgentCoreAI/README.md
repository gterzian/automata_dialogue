# AgentCoreAI

The Core AI engine that implements `Core`'s `AgentSession`, beside the MLX
`Agent`. Both backends hand the model's answer to `AgentDialogue`, so the
no-repeat window and the answer parsing are identical on either; the prompt and
the answer format belong to `Core/Agent/README.md`, and the MLX side to
`Agent/README.md`.

## Bundle

`CoreAIEngine` runs an exported Core AI bundle directory: a `metadata.json` of
kind `vlm`, the `.aimodel` assets it names (`main` decoder, `embedding`, and
`vision`), and the embedded tokenizer. The bundle must carry a vision encoder —
every input here is a drawing — and a bundle without one fails the run with
`CoreAIEngineError.notAVisionBundle` instead of running blind.

An MLX snapshot cannot be loaded here and a Core AI bundle cannot be loaded by
`Agent`: the two runtimes read different formats, so a comparison loads one
export of each.

## Export

A bundle is produced outside this software, from `apple/coreai-models`
(pinned revision in `Package.swift`):

```
uv run coreai.vlm.export qwen3-vl [--output-dir DIR]
```

Exporting and running both need macOS 27 (the package's minimum, and this app's).
The export downloads the checkpoint from Hugging Face and the `uv` environment
from PyPI, so it needs a network this repository's sandbox does not have. Keep
the result under `Models/`, named after the checkpoint (`Models/README.md`).

## Run

```
rater-cli bench --engine coreai --aimodel <bundle-dir> artifacts/
rater-cli rate  --engine coreai --aimodel <bundle-dir> artifacts/
```

`--engine` (or `RATER_ENGINE`) selects the backend and `--aimodel` (or
`RATER_AIMODEL_PATH`) the bundle; both default to the MLX backend and
`RATER_MODEL_PATH`.

## Prefix cache

The system prompt is the same on every run, so it is the prefix both backends
try to reuse. Whether Core AI can reuse it depends on the engine the exporter's
`vision.token_merge` selects (`LoadedBundle.reusesPrefix`):

- `decoder_gather` (Gemma 4 vision exports) builds the static-shape engine,
  which keeps a token history and rewinds to the longest matching prefix. Every
  run submits the whole prompt and only the tokens after the previous run's
  divergence are prefilled. The reported cache stops at the first image
  placeholder, whose embeddings belong to that run.
- `separate_embedding` (the Qwen-VL family, which `coreai.vlm.export` produces)
  builds the sequential VLM engine, which has no token history: its multimodal
  prefill embeds the whole token array it is given, and its decode loop indexes
  that same array by absolute position, so a call that skipped the cached prefix
  has no supported form. `CoreAIEngine` resets and prefills the whole prompt
  there, and reports `cachedPromptTokenCount: 0`.

A Qwen3-VL arm of a comparison therefore pays the system prompt on every
submission while the MLX arm pays it once. Compare the marginal run — the second
image onward — rather than the batch total, and read `bench`'s `of which N
prompt tokens came from the cached prefix` line before crediting a prefill
difference.

## Remaining work

- **No run has been executed on this engine.** It compiles against the pinned
  `coreai-models` revision, but the sandbox has no exported bundle and cannot
  make one (see Export). Treat the first `bench --engine coreai` as the smoke
  test: the prompt-token count should be the system prompt plus the image's
  visual tokens plus the user turn.
- **The same weights are not available as a vision bundle.** `coreai-models`
  exports Qwen3.5 as a text decoder only, and its vision-language recipes cover
  `qwen3-vl` (Qwen3-VL-2B-Instruct) and `muse-glimmer-vl`. An image comparison
  therefore puts Qwen3-VL-2B against the MLX Qwen3.5-4B; it measures the
  runtimes, not one model's weights.
- **The Qwen-VL prefix is only recoverable upstream.** Giving
  `CoreAISequentialVLMEngine` a token history, or a supported way to prefill a
  suffix at a cached offset, would let those bundles reuse the system prompt the
  way the static-shape engine does.
