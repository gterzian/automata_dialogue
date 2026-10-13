# Core/Session

The transcript model and its incremental-update machinery, adapted from
uni03C0's `Core/Session`. It is pure data (no AppKit): a host supplies
measurement closures and draws the materialized window. Nothing consumes it
today — the CLI does not use it.

## Entries

`TranscriptEntryKind`:

- `userInput(text:imagePath:)` — the submitted prompt and optional attachment.
- `choice(Choice)` — the chosen automaton.
- `assistantMessage(text:)` — the model's answer.
- `errorMessage(String)` — a red row below partial content.

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
