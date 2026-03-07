# End-to-End Agent Playbook (Informalize + AFTK)

This page shows the intended combined workflow:

- use **Informalize** to create blueprint placeholders + natural-language notes,
- use **AFTK** to query those notes (via hover) and explore tactic branches,
- then write a finalized tactic proof in Lean.

---

## 0) Setup

Build, run tests, install git safety hooks, install Bun deps for `lambda`, and ensure your workspace root has a `lambda.json`:

```bash
lake build
lake exe tests
./scripts/setup-git-hooks.sh
bun install
```

Minimal `lambda.json`:

```json
{
  "thinkingLevel": "off",
  "builtInTools": ["read", "bash", "edit", "write"]
}
```

Run the agent in print mode:

```bash
# inside this repository
bun run lambda "Summarize the current Lean goals"

# downstream Lake workspace using AFTK dependency
# lake run lambda -- "Summarize the current Lean goals"
```

The hook setup blocks both staged-sensitive commits and pushes that include
sensitive files such as `.envrc`.

If you are using upstream `pi` instead of `lambda`, install compatibility tools with:

```bash
lake run setup_pi_extension
```

---

## 1) Create a Lean placeholder tied to markdown notes

Create `PlaybookDemo.lean`:

```lean
import Informalize

theorem imp_id (P : Prop) : P → P := by
  have _strategy : True := by
    exact informal[Playbook.imp_id.strategy]
  exact informal[Playbook.imp_id.strategy]
```

Create `informal/Playbook/imp_id/strategy.md`:

```md
# imp_id strategy notes

Goal: prove `P → P`.

Initial plan:
1. `intro h`
2. `exact h`

Candidate branches to try:
- `intro h; exact h`
- `simpa`
```

Notes:

- `informal[Playbook.imp_id.strategy]` maps to `informal/Playbook/imp_id/strategy.md`.
- The informal term is a regular term placeholder (similar workflow role to `sorry`).

---

## 2) Query blueprint status with Informalize CLI

```bash
lake exe informalize status --module PlaybookDemo
lake exe informalize decl --module PlaybookDemo --decl PlaybookDemo.imp_id
lake exe informalize location --module PlaybookDemo --location Playbook.imp_id.strategy
```

This confirms that:

- the declaration is tracked,
- the location id is tracked,
- the reverse index location -> declaration is available.

---

## 3) Pull natural-language notes through AFTK hover

Use the AFTK tool calls (from `lambda`, or pi compatibility mode):

### Open file

Tool: `aftk_open`

```json
{
  "path": "PlaybookDemo.lean"
}
```

### Query hover at an informal term

(Using the snippet above, line 5/6 at `informal[...]`.)

Tool: `aftk_get_hover`

```json
{
  "path": "PlaybookDemo.lean",
  "line": 5,
  "col": 12
}
```

Expected: hover includes natural-language markdown content for `Playbook.imp_id.strategy`.

---

## 4) Load a tactic node and inspect current goals

Get node ids near the main placeholder tactic (`exact informal[...]` on line 6).

Tool: `aftk_load_node`

```json
{
  "path": "PlaybookDemo.lean",
  "line": 6,
  "col": 3
}
```

Pick one returned id (call it `<id0>`), then inspect:

Tool: `aftk_get_goals`

```json
{
  "path": "PlaybookDemo.lean",
  "id": "<id0>"
}
```

---

## 5) Explore tactic branches from the same start node

Try multiple candidates from `<id0>` and compare outcomes.

### Branch A

Tool: `aftk_run_tactic_steps`

```json
{
  "path": "PlaybookDemo.lean",
  "id": "<id0>",
  "tactics": ["intro h", "exact h"]
}
```

### Branch B

Tool: `aftk_run_tactic_steps`

```json
{
  "path": "PlaybookDemo.lean",
  "id": "<id0>",
  "tactics": ["simpa"]
}
```

Pick the branch with best goal progress (ideally zero goals).

Important: these branch states are **transient**. Use them for search, not as final proof artifacts.

---

## 6) Update markdown notes during exploration

As you explore, edit `informal/Playbook/imp_id/strategy.md` with what worked/failed, e.g.:

````md
## Exploration log

- `intro h; exact h` closes goal.
- `simpa` not reliable here.

Chosen final script:

~~~lean
intro h
exact h
~~~
````

This preserves reasoning context for later agent passes.

---

## 7) Commit final Lean proof text

Replace the main placeholder with the validated proof:

```lean
import Informalize

theorem imp_id (P : Prop) : P → P := by
  have _strategy : True := by
    exact informal[Playbook.imp_id.strategy]
  intro h
  exact h
```

At this point, the placeholder used for proof search is gone from the theorem body.
(You may keep or remove `_strategy` note anchors depending on your project policy.)

---

## Quick checklist

- [ ] `informal[...]` placeholder present and mapped to markdown.
- [ ] Informalize CLI confirms declaration/location tracking.
- [ ] AFTK hover recovers natural-language note context.
- [ ] Multiple tactic branches explored from one starting node.
- [ ] Notes updated with branch outcomes.
- [ ] Final tactic proof written explicitly in Lean.
