# Core/Agent

The pure agent logic: nothing here links MLX. The MLX VLM wrapper
(`AgentEngine`) is a separate `Agent` target that depends on `Core`.

## Per-input model

Each submitted input is one self-contained run: system prompt, one user turn
(image and optional text), then one plain-text answer. The model context holds
only the current input, so latency is constant and the system prompt is a
stable cacheable prefix.

## One answer, no tool call

There is no tool schema and no tool-dispatch round. The prompt asks for three
lines:

```
class: <one of repetition, nesting, randomness, complexity>
id: <one id from the section for that class>
reason: <one full sentence>
```

The `class` line comes first so the model commits to a class before choosing an
id; the id then comes from that class's section, and the reason names the same
class. The parser reads only `id:` and `reason:`; the class line is ignored.

`ChoiceParser.choice(from:)` reads the id, preferring the explicit `id:` field
and otherwise taking the first catalog id anywhere in the text (longest match
first, so `E90.sparse` beats `E90`). There is no repair pass: an answer with no
usable id (unknown, or recently used) ends the run in `.failed`, and a terse
reason is accepted as written. Text beyond the parsed fields is ignored. The
parser is pure, so the MLX engine and the tests share one implementation.

## No repeats

The dialogue must not replay the same automaton. The engine carries a
`ChoiceHistory` of the last 20 chosen ids across runs and, before each run,
builds the user turn with `ChoiceHistory.userTurn(_:)`, which appends a note
that the listed ids were used recently and that an answer using one is invalid.
That note rides with the image in the user turn, so the system prompt stays a
cacheable prefix. The engine treats an excluded id the same as an unknown one:
the run fails without recording a choice.

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
match, and an unknown id), the prompt's class descriptions and the per-class id
sections, and the prompt budget.
