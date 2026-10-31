# Automata Rater

A macOS command-line tool that answers a drawing or image with one of 111
curated cellular automata. A local MLX vision-language model chooses the entry
whose class of behavior matches what it sees, and each run excludes the recent
choices so the answer stays varied.

## Requirements

- Apple Silicon Mac on macOS 26 or later.
- Xcode with the Swift 6.4 toolchain and the Metal toolchain component.
- About 3 GB free for the 4B model snapshot, plus SwiftPM's build output.
- Network access for the Metal toolchain component, the SwiftPM dependencies,
  and the model snapshot.

## Setup from scratch

Clone the repository, then run these commands from its root. The order
matters: `resolve` fetches the dependency checkouts, the `mlx-c` submodule
inside `mlx-swift` is not populated by SwiftPM, and the Metal component supplies
the `metal` compiler that `Cmlx` needs.

```sh
xcodebuild -downloadComponent MetalToolchain

swift package resolve --disable-sandbox
git -C .build/checkouts/mlx-swift submodule update --init Source/Cmlx/mlx-c

swift build --disable-sandbox -c release
swift test --disable-sandbox
```

The release build writes `.build/release/rater-cli`.

## Install the 4B model

This guide uses `Models/Qwen3.5-4B-MLX-4bit`, a 4-bit MLX conversion of
`Qwen/Qwen3.5-4B`; the snapshot directories are git-ignored. The engine is
local-only (see `AGENTS.md` → Product decisions), so the directory must already
exist. `Models/README.md` records the verified file list, commit, and weight
hash.

The conversion used for the verified snapshot is:

```sh
python3 -m mlx_vlm convert \
  --hf-path Qwen/Qwen3.5-4B \
  --mlx-path Models/Qwen3.5-4B-MLX-4bit \
  -q --q-bits 4 --q-group-size 64
```

The verified conversion used mlx-vlm's `pc/fix-qwen35-predicate` branch. After
converting, compare
`shasum -a 256 Models/Qwen3.5-4B-MLX-4bit/model.safetensors` with the hash in
`Models/README.md`. A snapshot kept elsewhere is fine: pass its directory with
`--model` or `RATER_MODEL_PATH`.

## Run the CLI

Point the CLI at the snapshot once per shell:

```sh
export RATER_MODEL_PATH="$PWD/Models/Qwen3.5-4B-MLX-4bit"
```

Rate the reference drawings in the review window:

```sh
.build/release/rater-cli rate artifacts/
```

`rate` opens the window on the drawing page; `CLI/README.md` documents the
flags and the window controls. The headless commands time and score the same
images without a window:

```sh
.build/release/rater-cli bench artifacts/
.build/release/rater-cli classify artifacts/
```

Print the catalog without loading a model:

```sh
.build/release/rater-cli catalog
```

The first submission is slower than later ones while MLX compiles its Metal
kernels and the process prefills the system prompt. Measured costs are in
`Agent/README.md`.

## Troubleshooting

Build failures and the environment-specific fixes are collected in
`AGENTS.md` → Build and test (the `metal` shim, a stale Metal toolchain path in
`.build`, and an empty `mlx-c` submodule).

## License

MIT; see `LICENSE`.
