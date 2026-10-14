# Core

AppKit-free foundation of the CLI: catalog, agent prompt/parsing, image import,
and the Metal render core. Built by SwiftPM for tests and the CLI.

## Constraints

- **AppKit-free.** `Core` compiles without AppKit so it stays testable and so
  the render core can run headless. Anything that needs a view or an
  `NSView`-backed layer lives in `CLI`.
- **No external package dependencies.** The MLX VLM lives in a separate
  `Agent` target that depends on `Core`, never the reverse.
- Default actor isolation is `nonisolated` (see `AGENTS.md` for the repo-wide
  concurrency rules).

## Layout

- `Catalog/` — the 111 `ProgramSpec` entries, behavior classes, GPU program
  descriptors, palettes, and the catalog index. See `Catalog/README.md`.
- `Agent/` — the `Choice` type, the plain-text answer parser, and
  system-prompt assembly. See `Agent/README.md`.
- `Import/` — dragged-in image attachments and normalization to the model's
  square input (512 px by default). See `Import/README.md`.
- `Render/` — geometry, the frame-sink seam, and the Metal 4 simulation core.
  See `Render/README.md`.
