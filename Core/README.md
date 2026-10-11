# Core

AppKit-free foundation of the app: catalog, CPU reference programs, agent
prompt/schema/dispatch logic, image import, transcript store, and the Metal
render core. Built by SwiftPM for tests and by the Xcode project as a framework
for the app.

## Constraints

- **AppKit-free.** `Core` compiles without AppKit so it stays testable and so
  the render core can run headless. Anything that needs a view or an
  `NSView`-backed layer lives in `Client`.
- **No external package dependencies.** The MLX VLM lives in a separate
  `Agent` target that depends on `Core`, never the reverse.
- Default actor isolation is `nonisolated` (see `AGENTS.md` for the repo-wide
  concurrency rules).

## Layout

- `Catalog/` — the 106 `ProgramSpec` entries, behavior classes, GPU program
  descriptors, palettes, and the catalog index. See `Catalog/README.md`.
- `Programs/` — CPU reference implementations and the PRNG. See
  `Programs/README.md`.
- `Agent/` — the `Choice` type, the plain-text answer parser, and
  system-prompt assembly. See `Agent/README.md`.
- `Import/` — dragged-in image attachments and normalization to the model's
  512×512 input. See `Import/README.md`.
- `Session/` — transcript entries, the append-only store, the streaming
  refresh gate, and the height cache. See `Session/README.md`.
- `Render/` — geometry, the frame-sink seam, the CPU reference renderer, and
  the Metal 4 simulation core. See `Render/README.md`.
