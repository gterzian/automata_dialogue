# Models

Model weights for the two backends, each loaded from a directory that is
already present: `Agent` reads a Hugging Face MLX snapshot
(`AgentEngine.Configuration.modelDirectory`), `AgentCoreAI` an exported Core AI
bundle (`CoreAIEngine.Configuration.bundleDirectory`); see `Agent/README.md` and
`AgentCoreAI/README.md`. The directories are git-ignored; only this file is
tracked, so the verified hashes stay with the repo. The software never
downloads a model: it loads a directory that is already present, or fails.

## Verified snapshots

Fetched with `hf download` / `huggingface-cli download`, then checked against
the hub hashes each snapshot's `.cache/huggingface/` records. Re-run the check
by hashing the file (`shasum -a 256 <file>`) and comparing to the `lfs_sha256`
in the snapshot's `trees/*.json`; non-LFS files compare against their
`blob_id`.

| snapshot | commit | weights (SHA-256) |
|---|---|---|
| `Qwen3.5-9B-4bit` | `8b2b98c00a6b4d291155e4890773ca8f769aee53` | `model-00001-of-00002.safetensors` `a68b87558c6ef43f74c2bd63ce7e9092ceddc3101f3def0030774bae5f42aadd`<br>`model-00002-of-00002.safetensors` `b0a770bf8469c7f3f18756a0e0283f1c1174344a83e059a4e483f6af4907352d` |
| `Qwen3.5-4B-MLX-4bit` | `32f3e8ecf65426fc3306969496342d504bfa13f3` | `model.safetensors` `5fb9acd0246866381cf8c5c354c6db1019f6498eec4ccb4f5edcc71ffeacb2db` |
| `gemma-4-e2b-it-4bit` | `238767527555cb75a05732a84dff5d6ba0dd6809` | `model.safetensors` `038e39a37a7667373d2c3991375446b10c96ae1d717a68674870343db376b76e` |

The Qwen `chat_template.jinja` files are the stock Qwen template (blob
`a585dec894e6…`). The Gemma template is the upstream Gemma 4 template
(blob `c19999a347da…`); it emits `<|think|>` only when `enable_thinking` is
true, so the engine's `additionalContext: ["enable_thinking": false]` turns
thinking off there too. None of the snapshots defines remote code (`auto_map`
absent, no `.py` files), and the weights are safetensors (a JSON header plus
raw tensor bytes — no pickle).

The commit column records which snapshot was verified; it is not a runtime pin,
since the engine loads the directory as-is.

## Running a snapshot

The MLX engine loads a snapshot directory (`--model` or `RATER_MODEL_PATH`) and
has no downloader, so the directory must already exist or the run fails. The 4B
snapshot (`Models/Qwen3.5-4B-MLX-4bit`) is the recommended one. The engine's
prompt, answer parsing, and `enable_thinking` context are model-agnostic, and
mlx-swift-lm registers `gemma4` in its VLM factory, so a Gemma 4 snapshot runs
through the same path. A relative `--model` path resolves against the current
directory.

## Core AI bundles

A Core AI bundle is a directory of `.aimodel` assets plus `metadata.json`, made
outside this software from a checkpoint (`AgentCoreAI/README.md` records the
export). It sits beside the snapshots under `Models/` and is git-ignored the
same way. Name it after the checkpoint it was exported from, since the bundle
is a build artifact of that checkpoint rather than a file whose hash identifies
it.

## Remaining work

- The recommended snapshot is `Models/Qwen3.5-4B-MLX-4bit`; re-check the choice
  when the prompt or an example changes (`Agent/README.md`).
