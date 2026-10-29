# Core/Import

Turns a file or a freehand drawing into the model's input, and produces the
raster the submission beat uploads. AppKit-free: decoding and drawing use
ImageIO/CoreGraphics, not `NSImage`.

## Inputs

A file arrives as a `URL`. A drawing arrives as a `Drawing`: normalized
top-left points plus the aspect of the surface that captured them, so any
pointer source can fill it (the CLI's canvas is one adapter). The prompt judges
the drawn shapes rather than the page, so a drawing keeps the surface's dark
page and light strokes.

`DrawingImage.raster` aspect-fits a drawing into the target size, so a square
model input keeps the shapes proportional.

## Normalized input

1. A file goes through `ImageImport.normalize(_:into:dimension:)`, which decodes
   it, scales it (aspect-fit, centered on white) to a square of `dimension`
   pixels (512 by default, overridable through the engine's `imageDimension`),
   and writes a PNG into the session's temp folder:
   `<tmp>/Rater/<session-id>/drawing-<uuid>.png`. The drawing overload renders
   the strokes at that square size.
2. The caller passes that path as `AgentInput.imageURL`.
3. On close, the session's temp folder is removed; at launch, temp session
   folders with no open session are purged.

Normalization and raster rendering are called off the main thread by the
review loop.

## Reference labels

`ReferenceLabels.load(forPaths:)` reads the `examples.json` manifest in an
image's directory and maps its path to the `Behavior` it illustrates. The CLI
shows that class in the carousel; the manifest is display metadata, so the
normalized model input still contains only the drawing. A directory with no
manifest labels nothing, while a manifest that cannot be decoded throws instead
of silently dropping every label.

## Submission raster

The review window plays the submission beat from a `RasterImage`, tightly
packed RGBA8 pixels that upload straight to a texture. `rasterImage(from:)`
bounds a file decode for the screen, and `DrawingImage.raster` renders a
drawing at the surface's aspect. The model still reads the normalized PNG, so
the beat's texture and the model's input are independent views of the same
input.

## Notes

- `purgeStaleSessions(keeping:)` deletes every folder under its root. Purging
  the real `<tmp>/Rater` while another process (a `rater-cli rate` run) holds a
  live session deletes that session's images mid-run, so the test suite passes
  a scoped `root`.
