# Core/Agent

The pure agent logic: nothing here links MLX. The MLX VLM wrapper
(`AgentEngine`) is a separate `Agent` target that depends on `Core`.

## Per-input model

Each submitted input is one self-contained run: system prompt, one user turn
(image and optional text), then the three tool calls. The full session history is
shown in the transcript, but the model context holds only the current input,
so latency is constant and the system prompt is a stable cacheable prefix.

## Tools and ordering

Three tools in a fixed order. `ToolDispatcher` is a small state machine, one per
run:

```
awaitingRating ──rate_input(valid)──► rated(label) ──list_automata──► listed(label) ──choose_automaton(valid)──► done
```

- The catalog is **never** in the prompt or a tool schema. `list_automata`
  returns only the entries whose `Behavior` the label allows, so the model
  sees a small, label-scoped list and the token cost does not grow with the
  inventory. `choose_automaton.id` is a plain string validated by the
  dispatcher.
- The package's validation default is `.permissive`, so schema violations
  reach the dispatcher. **The dispatcher validates arguments itself and always
  returns a corrective string** — it never throws, because a throw from the
  tool closure ends the stream with an error.
- `choose_automaton` before `list_automata` returns an ordering message, so the
  model must read the candidate list before choosing.
- An id outside the behaviors allowed for the label returns the valid id list.
- After `done`, the agent writes one closing sentence.
- The dispatcher counts calls; at the eighth call without reaching `done` it
  emits `.failed` and the engine cancels.

The user-visible order (rating card, then choice card) is identical on every
run whatever the model does.

## Prompt

`SystemPrompt.build()` joins two parts into one immutable string: the short
procedure (rate, list, choose) and the verbatim rating rubric (with the *Output
format* section reframed to the `rate_input` fields and the multi-input summary
dropped). See the rubric artifact for the source text. Keep the catalog out of
this string — it belongs in the `list_automata` result.

## Events

`AgentEvent`: `.text` (closing sentence, batched by the UI), `.rating`,
`.choice`, `.finished`, `.failed`. `AgentInput` carries `text` and an optional
`imageURL`.

## Tests

Ordering (`rate → list → choose`, and each call out of order), label-scoped
listing, argument/id validation, event emission, loop bound, and
`RejectedToolCallError` handling.
