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

Both `chat_template.jinja` files are the stock Qwen template (blob
`a585dec894e6…`); neither snapshot defines remote code, and the weights are
safetensors (a JSON header plus raw tensor bytes — no pickle).

The 9B commit pins the default model's download
(`Configuration.pinnedRevision(for:)`); a mutable ref like `main` would let the
hub serve different weights on a later run.

## Remaining work

- `Configuration.fallbackModelID` is `mlx-community/Qwen3.5-4B-4bit`, which is
  not what `Qwen3.5-4B-MLX-4bit` is: that snapshot is the community conversion
  (per its `README.md`). The fallback is unpinned and unverified here; fetch
  and hash its snapshot before relying on it.
