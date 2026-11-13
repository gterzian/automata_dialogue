# Automata Rater

A macOS command-line tool that answers a drawing or image with one of 111
curated cellular automata. A local MLX vision-language model chooses the entry
whose class of behavior matches what it sees, and each run excludes the recent
choices so the answer stays varied.

## Requirements

- Apple Silicon Mac on macOS 26 or later.
- Xcode with the Swift 6.4 toolchain and the Metal toolchain component.
- About 6 GB free for the 9B model snapshot, plus SwiftPM's build output.
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

## Install the 9B model

This guide uses `../Models/Qwen3.5-9B-4bit`, the hub's
`mlx-community/Qwen3.5-9B-4bit` conversion of `Qwen/Qwen3.5-9B-Base`, from the
snapshot directory outside this repository; the paths below resolve from the
repository root, and `../Models/README.md` records the verified file list,
commit, and weight hashes. The engine is local-only (see `AGENTS.md` → Product
decisions), so the directory must already exist.

The snapshot comes from the Hugging Face hub, fetched by a command you run:
`rater-cli` never talks to the network. The Hub CLI is `hf`
(`pip install -U huggingface_hub`, or Homebrew's `hf` formula):

```sh
hf download mlx-community/Qwen3.5-9B-4bit --local-dir ../Models/Qwen3.5-9B-4bit
```

`--local-dir` writes the files flat, the way the engine reads a snapshot.
`../Models/README.md` lists the other verified snapshots with their repository
ids and commits.

After downloading, compare `shasum -a 256` of
`../Models/Qwen3.5-9B-4bit/model-00001-of-00002.safetensors` and
`model-00002-of-00002.safetensors` with the hashes in `../Models/README.md`. A
snapshot kept elsewhere is fine: pass its directory with `--model` or
`RATER_MODEL_PATH`.

## Run the CLI

Point the CLI at the snapshot once per shell:

```sh
export RATER_MODEL_PATH="$PWD/../Models/Qwen3.5-9B-4bit"
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

At launch the CLI loads the model, prefills the system prompt, and runs one
image turn at the same image size and sampling the review uses, so the vision
encoder, the prefill, and the one-token decode step are compiled before the
first submission. The window opens on the collapse intro, repeating it and
accepting no input until that warm-up finishes; the first page then appears and
the first submission costs its own turn. Measured costs are in
`Agent/README.md`.

## Troubleshooting

Build failures and the environment-specific fixes are collected in
`AGENTS.md` → Build and test (the `metal` shim, a stale Metal toolchain path in
`.build`, and an empty `mlx-c` submodule).

## License

MIT; see `LICENSE`.
