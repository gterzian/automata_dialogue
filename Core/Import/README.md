# Core/Import

Image input without an in-app canvas: the user drags a file onto the input and
it becomes an attachment on the next agent turn.

## Attachment lifecycle

1. A drop provides a file `URL`. `ImageImport.normalize(_:into:)` decodes it,
   scales it to **512×512** (the model's configured image size, design doc
   §3.1), and writes a PNG into the session's temp folder:
   `<tmp>/Rater/<session-id>/drawing-<uuid>.png`.
2. The prompt input holds an `ImageAttachment` (source name + normalized path)
   and shows a thumbnail chip.
3. On send, the transcript input row references the normalized path. The agent
   receives that path as `AgentInput.imageURL`.
4. On close, the session's temp folder is removed; at launch, temp session
   folders with no open session are purged.

Normalization runs off the main thread. A row whose file has disappeared shows
a quiet placeholder tile of the same size rather than failing.

## Notes

- Core is AppKit-free: decoding uses ImageIO/CoreGraphics, not `NSImage`.
- A non-image drop is rejected with a short message; the input keeps its state.
