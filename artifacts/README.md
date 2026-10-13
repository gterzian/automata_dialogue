# artifacts

Source material.

- `Curated Inventory of Cellular Automata.md` — the four behavior classes and
  the 111 entries (id, look, class). `Core/Agent/SystemPrompt` is built from the
  same entries.
- `System prompt_ choosing an automaton.md` — the source for
  `Core/Agent/SystemPrompt.swift`.

The four class names describe the **picture** each entry draws from its stated
start, not the rule's class in Wolfram's classification (NKS ch. 6). The
catalog follows the picture where they differ: a class-4 rule reads as
`repetition` when its chosen start is periodic (`T1662`; K2R2 code 20 seed 195,
whose period-22 fixed structure NKS shows on p. 283), and `randomness` also
covers class-2 pictures whose fixed marks are scattered irregularly
(`E232.rand`).
