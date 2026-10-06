# Client

The macOS app. AppKit + SwiftUI, `MainActor` by default. Built by the Xcode
project (`project.yml`), not by SwiftPM.

## Shape (v1)

One window, one panel, following the uni03C0 conventions for chrome:

- The panel fills the window. While an automaton is running it shows the
  automaton; otherwise it shows the transcript.
- The input is a floating glass surface pinned to the bottom. **Drag an image
  file onto the input to attach it.** There is no in-app drawing surface.
- A submitted prompt immediately stops any running automaton, then starts a
  new agent run.
- Transcript rows (user input, rating card, choice card, assistant sentence,
  error) render in the same panel.

The transcript is rendered by an `NSTableView`-backed coordinator (as in
uni03C0) driven by `Core/Session`. Only the visible window of rows is
materialized; heights come from `Core`'s `HeightCache`.

## Automaton panel

`AutomatonPanelView`'s role is filled by `AutomatonView` (an `NSViewRepresentable`
over `AutomatonNSView`), which draws the `CGImage` produced by `Core`'s
`IncrementalRenderer`. `RaterModel` owns the agent run and the animation task:
on a `.choice` event it starts the entry and advances the renderer ~30 times a
second; a new `send()` calls `stopAutomaton()` first, so the running automaton
stops immediately. The Metal `CAMetalDisplayLink` layer sink is pending (see
`Core/Render/README.md`).
