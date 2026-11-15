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
reason: <one full English sentence>
reason_zh: <the same reason in one Simplified Chinese sentence>
```

The model rates the picture's class of behavior; it never names an automaton,
so the prompt carries no catalog. The class line comes first so the model
commits to a class before writing the reason, and the reason names the same
class. An answer that omits the Chinese line leaves it empty and the rating
still stands.

`RatedClassParser.ratedClass(from:)` reads the class, preferring the explicit
`class:` field and otherwise taking the first class word anywhere in the text
(whole words only). It reads `reason:` and `reason_zh:`; text beyond the parsed
fields is ignored. There is no repair pass: an answer with no class ends the run
in `.failed`, and a terse reason is accepted as written. The parser is pure, so
the MLX engine and the tests share one implementation.

## Random pick, no repeats

`SessionChoices` records every id shown in the session. For each rated class it
takes the catalog entries of that class the session has not shown, picks one
uniformly at random, and records it, so the model's rating alone decides the
class and the engine decides the entry. When a class is exhausted, its shown
ids are cleared first: the class outranks the no-repeat rule, and the smallest
class is only 14 entries. The model never sees this state; the user turn carries
only the submitted text, so the prompt stays a cacheable prefix. `Choice`
carries the picked id, the rated class, and the two reasons.

## Prompt

`SystemPrompt.build()` joins two parts into one immutable string: the four
behavior classes described plainly, and the answer format. The rubric reserves
`complexity` for a picture that contains both an ordered and a disordered part
of different kinds (or localized structures inside a different texture); a
wholly ordered figure, even a recognizable one such as a house or a glyph, is
`repetition` or `nesting`. Those two split on the copies' sizes: copies at one
size are `repetition`, and copies at different sizes are `nesting`, whether the
copies nest inside one another or sit apart. The size comparison is stated
before the broad "one shape repeated" signal, because scaled copies fit that
signal too: without the comparison, separated triangles such as
`example_4.png` read as `repetition`. The string is identical on every run, so
it is a cacheable prefix; `AgentEngine` prefills it once into a KV cache and
copies that prefix for each run (see `Agent/README.md`). The prompt names no
automaton and no id: the class is what the model rates, and `SessionChoices`
supplies the entry.

## Events

`AgentEvent`: `.text` (the model's full answer, batched by the UI), `.metrics`
(one generation pass's prefilled and cached prompt token counts and times),
`.choice`, `.finished`, `.failed`. `AgentInput` carries `text` and an optional
`imageURL`.

## Tests

Class parsing (the `class:` field, markdown, the prose fallback, whole-word
matching, and the reasons), the prompt's class descriptions (including the size
split between `repetition` and `nesting` and the order of its signals), the
answer format, that the prompt names no automaton, and the prompt budget. The
session's random pick is covered by `SessionChoicesTests`: an entry of the rated
class, no repeat before the class is exhausted, and the class-only reset when
it is.
