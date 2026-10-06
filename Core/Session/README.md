# Core/Session

The transcript model and its incremental-update machinery, adapted from
uni03C0's `Core/Session`. It is pure data (no AppKit): the view coordinator in
`Client` supplies measurement closures and renders the materialized window.

## Entries

`TranscriptEntryKind`:

- `userInput(text:imagePath:)` — the submitted prompt and optional attachment.
- `rating(Rating)` — the `rate_input` card.
- `choice(Choice)` — the `choose_automaton` card.
- `assistantMessage(text:)` — the closing sentence.
- `errorMessage(String)` — a red row below partial content.

`rating` and `choice` render through the client's `ToolCallCardView` (tool
names `rate_input` / `choose_automaton`).

Entry `id`s are stable so the table distinguishes an in-place reconfigure from
a new row insert.

## Store

`TranscriptStore` owns the full, ordered history off-main and exposes a
windowed view for the coordinator. Records persist as append-only JSONL. The
store's input is `apply(_ event: AgentEvent)` (replacing uni03C0's
`apply(RPCFrame)`); `rebuild(from:)` reloads a persisted transcript.

## Refresh gate

`StreamingRefreshGate` batches streaming text at 0.25 s, refreshes the first
chunk immediately, and always refreshes on the streaming→final flag flip.
Copy the gate from uni03C0; it is already unit-tested there.

## Height cache

`HeightCache` keys measured row heights by `(id, width, contentTag)` so a
streaming row is re-measured only on genuine content change. Flat rows use a
nil tag; a nil-tag query never hits a content-tracked entry.
