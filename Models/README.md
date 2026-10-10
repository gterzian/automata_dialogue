# Models

Local Hugging Face snapshots, loaded through
`AgentEngine.Configuration.modelDirectory` (see `Agent/README.md`). The
snapshot directories are git-ignored; only this file is tracked, so the
verified hashes and the revision pin stay with the repo.

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

The 4B and 9B commits pin their downloads
(`Configuration.pinnedRevision(for:)`); the 4B is the default. A mutable ref
like `main` would let the hub serve different weights on a later run.

## Running a snapshot

Point the app or CLI at the directory (`--model`/`RATER_MODEL_PATH`), not at
the hub id; see `Agent/README.md`. The engine's prompt, answer parsing, and
`enable_thinking` context are model-agnostic, and mlx-swift-lm registers
`gemma4` in its VLM factory, so a Gemma 4 snapshot runs through the same path.
A relative `--model` path resolves against the current directory.

## Remaining work

- `Configuration` now defaults to the 4B; the old
  `mlx-community/Qwen3.5-4B-4bit` fallback is gone. Re-check the 4B snapshot's
  pin if the default ever changes.
