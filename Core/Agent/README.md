# Core/Agent

The pure agent logic: nothing here links MLX. The MLX VLM wrapper
(`AgentEngine`) is a separate `Agent` target that depends on `Core`.

## Per-input model

Each submitted input is one self-contained run: system prompt, one user turn
(image and optional text), then one plain-text answer. The model context holds
only the current input, so latency is constant and the system prompt is a
stable cacheable prefix.

## One answer, no tool call

There is no tool schema and no tool-dispatch round. The prompt asks for two
lines:

```
id: <one id from the list>
reason: <one sentence>
```

`ChoiceParser.choice(from:)` reads the id, preferring the explicit `id:` field
and otherwise taking the first catalog id anywhere in the text (longest match
first, so `E90.sparse` beats `E90`). The engine gives one **repair turn**: if the
first answer names no usable id (unknown, or recently used), it appends a
correction and asks again, and only a second miss ends the run in `.failed`.
Text beyond the two fields is ignored. The parser is pure, so the MLX engine and
the tests share one implementation.

## No repeats

The dialogue must not replay the same automaton. The engine carries a
`ChoiceHistory` of the last 20 chosen ids across runs and, before each run,
builds the user turn with `ChoiceHistory.userTurn(_:)`, which appends "do not
choose these ids" to the text. That note rides with the image in the user turn,
so the system prompt stays a cacheable prefix. The engine treats an excluded id
the same as an unknown one: it triggers the one repair turn, then records the
accepted id.

## Prompt

`SystemPrompt.build()` joins three parts into one immutable string: the four
behavior classes described plainly, the flat catalog
(`Catalog.promptIndexLines`, one line per entry as `id | class`), and the
answer format. The rubric reserves `complexity` for a picture that contains
both an ordered and a disordered part (or localized structures inside a
different texture); a wholly ordered figure, even a recognizable one such as a
house or a glyph, is `repetition` or `nesting`. Each entry carries its own
class instead of being grouped, so the model does not have to map a separate
class table onto a listing. The string is identical on every run, so it is a
cacheable prefix. The per-entry `look` sentence stays in `Catalog` for the
inventory sync but is not submitted: the class is what the model matches, and
the prompt's ~1k-token budget assumes the listing is `id | class`.

## Events

`AgentEvent`: `.text` (the model's full answer, batched by the UI), `.metrics`
(one generation pass's prompt and generation token counts and times, so a repair
turn shows as a second event), `.choice`, `.finished`, `.failed`. `AgentInput`
carries `text` and an optional `imageURL`.

## Tests

Choice parsing (the `id:` field, markdown, fallback to prose, the longest-id
match, an unknown id), the prompt's class descriptions and per-entry class
lines, and the prompt budget.
