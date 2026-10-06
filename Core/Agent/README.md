# Core/Agent

The pure agent logic: nothing here links MLX. The MLX VLM wrapper
(`AgentEngine`) is a separate `Agent` target that depends on `Core`; `Core`
ships a deterministic `HeuristicAgent` so the app runs with no model present.

## Per-input model

Each submitted input is one self-contained run: system prompt, one user turn
(image and optional text), then the two tool calls. The full session history is
shown in the transcript, but the model context holds only the current input,
so latency is constant and the system prompt is a stable cacheable prefix.

## Tools and ordering

Two tools in a fixed order. `ToolDispatcher` is a small state machine, one per
run:

```
awaitingRating ──rate_input(valid)──► rated(label) ──choose_automaton(valid)──► done
```

- The package's validation default is `.permissive`, so schema violations
  reach the dispatcher. **The dispatcher validates arguments itself and always
  returns a corrective string** — it never throws, because a throw from the
  tool closure ends the stream with an error.
- `choose_automaton` before `rate_input` returns an ordering message; when the
  model emits both in one pass the first message teaches the next pass.
- An id outside the behaviors allowed for the label returns the valid id list.
- After `done`, the agent writes one closing sentence.
- The dispatcher counts calls; at the sixth call without reaching `done` it
  emits `.failed` and the engine cancels.

The user-visible order (rating card, then choice card) is identical on every
run whatever the model does.

## Prompt

`SystemPrompt.build(catalog:)` assembles three parts into one immutable
string: the short procedure, the verbatim rating rubric (with the *Output
format* section reframed to the `rate_input` fields and the multi-input summary
dropped), and the rating→inventory table plus the generated index. See the
rubric artifact for the source text.

## Events

`AgentEvent`: `.text` (closing sentence, batched by the UI), `.rating`,
`.choice`, `.finished`, `.failed`. `AgentInput` carries `text` and an optional
`imageURL`.

## Tests

Ordering (including both calls in one pass), argument/id validation, event
emission, loop bound, and `RejectedToolCallError` handling.
