# Core/Agent

The pure agent logic: nothing here links MLX or Core AI. The two runtimes are
separate targets — `Agent` and `AgentCoreAI` — that depend on `Core`.

## Backends

`AgentRunning` is one input's event stream. `AgentSession` adds the batch
lifecycle the CLI needs: `prepare()` before the first run, `resetHistory()`
between independent inputs, and `backend` (`mlx` or `coreAI`). The CLI holds an
`AgentSession`, so a backend swap is invisible to the review loop.

`AgentDialogue` is the bookkeeping both backends share: `turn(for:)` returns the
user turn and the ids its answer may not use, and `accept(_:excluding:)` parses
the answer, rejects a repeated or unknown id, and records the accepted one. Each
engine owns one and passes its model's answer through it, so the no-repeat
dialogue behaves the same whichever runtime produced the tokens. It lives here
because `CoreTests` covers it without either engine.

## Per-input model

Each submitted input is one self-contained run: system prompt, one user turn
(image and optional text), then one plain-text answer. The model context holds
only the current input, so latency is constant and the system prompt is a
stable cacheable prefix.

## Prefix reuse

The system prompt is identical on every run, so a backend prefills it once and
reuses it. `PromptPrefix.reusableLength(of:after:imageTokenID:)` is the rule for
deriving that length from a prompt: the leading tokens two prompts share,
stopping at the first image placeholder, because an image's embeddings belong to
the run that encoded them. The MLX backend's KV cache holds exactly the system
prefix; the Core AI backend applies the rule where its engine keeps a token
history (see `AgentCoreAI/README.md`).

## One answer, no tool call

There is no tool schema and no tool-dispatch round. The prompt asks for four
lines:

```
class: <one of repetition, nesting, randomness, complexity>
id: <one id from the section for that class>
reason: <one full English sentence>
reason_zh: <the same reason in one Simplified Chinese sentence>
```

The `class` line comes first so the model commits to a class before choosing an
id; the id then comes from that class's section, and the reason names the same
class. The parser reads `id:`, `reason:`, and `reason_zh:`; the class line is
ignored. The Chinese line repeats the reason for the review window, which shows
both; an answer that omits it leaves the Chinese line empty and the choice
still stands.

`ChoiceParser.choice(from:)` reads the id, preferring the explicit `id:` field
and otherwise taking the first catalog id anywhere in the text (longest match
first, so `E90.sparse` beats `E90`). There is no repair pass: an answer with no
usable id (unknown, or recently used) ends the run in `.failed`, and a terse
reason is accepted as written. Text beyond the parsed fields is ignored. The
parser is pure, so the MLX engine and the tests share one implementation.

## No repeats

The dialogue must not replay the same automaton. `AgentDialogue` keeps a
`ChoiceHistory` of the last 20 chosen ids across runs; `AgentDialogue.turn(for:)`
appends a note listing them and that an answer using one is invalid. That note
rides with the image in the user turn, so the system prompt stays a cacheable
prefix. A repeated id is treated like an unknown one: the run fails without
recording a choice.

## Prompt

`SystemPrompt.build()` joins three parts into one immutable string: the four
behavior classes described plainly, the catalog grouped by class
(`Catalog.promptIndexLines`, a `### <class>` heading followed by that class's
ids), and the answer format. The rubric reserves `complexity` for a picture
that contains both an ordered and a disordered part of different kinds (or
localized structures inside a different texture); a wholly ordered figure, even
a recognizable one such as a house or a glyph, is `repetition` or `nesting`.
Grouping puts the class next to the ids it contains, so the model chooses inside
the class it decided instead of reading a class column at the end of each line. The string
is identical on every run, so it is a cacheable prefix; `AgentEngine` prefills
it once into a KV cache and copies that prefix for each run (see
`Agent/README.md`). The per-entry `look` sentence stays in `Catalog` for the
inventory sync but is not submitted: the class is what the model matches, and
the prompt budget assumes the listing is grouped ids.

## Events

`AgentEvent`: `.text` (the model's full answer, batched by the UI), `.metrics`
(one generation pass's prefilled and cached prompt token counts and times),
`.choice`, `.finished`, `.failed`. `AgentInput` carries `text` and an optional
`imageURL`.

## Tests

Choice parsing (the `id:` field, markdown, fallback to prose, the longest-id
match, and an unknown id), `AgentDialogue`'s window and accept/reject rules,
`AgentBackend`'s argument parsing, the reusable prompt prefix and where it
stops, the prompt's class descriptions and the per-class id sections, and the
prompt budget.
