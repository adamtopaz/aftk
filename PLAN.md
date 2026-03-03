# PLAN: Add infotree-based hover + infoview-style handlers

## 1) Research summary (Lean 4 LSP behavior)

### 1.1 Hover in Lean LSP
From `Lean/Server/FileWorker/RequestHandling.lean` (`handleHover`):

- LSP resolves position to UTF-8 position.
- It finds the relevant command snapshot (`withWaitFindSnap ...`).
- It tries **parser docstring fallback** first (by traversing syntax stack and calling `findDocString?` on syntax kinds).
- It then queries infotree using:
  - `InfoTree.hoverableInfoAtM?`
  - and formats via `Info.fmtHover?`.
- If both parser-doc and infotree hover exist, it prefers infotree when sufficiently specific.
- Output is markdown (`MarkupKind.markdown`).

Key infotree APIs used:
- `InfoTree.hoverableInfoAtM?` (in `Lean/Server/InfoUtils.lean`)
- `Info.fmtHover?` (same file)

### 1.2 InfoView-relevant content in Lean LSP
From `Lean/Server/FileWorker/RequestHandling.lean`:

- `handlePlainGoal` (LSP method `$/lean/plainGoal`):
  - Computes goals at cursor using infotree (`InfoTree.goalsAt?` via `findGoalsAt?` helper).
  - Returns plain goal strings (`goals`) + markdown rendering (`rendered`).
- `handlePlainTermGoal` (LSP method `$/lean/plainTermGoal`):
  - Uses `InfoTree.termGoalAt?` and computes expected type in context.
  - Returns plain string goal + range.

These are the right references for **plain-text, non-widget** behavior.

### 1.3 What we should avoid for this task
Lean LSP also serves widget/RPC endpoints (`Lean.Widget.*`) used by VS Code InfoView. Those can include rich structures intended for frontend rendering. For this task, we should stay with plain text outputs (hover text, goals, term goals).

---

## 2) Gap analysis vs current AFTK file worker

Current AFTK file worker:
- Has static context: input text + `infoTrees`.
- No incremental snapshot machinery (`EditableDocument`, `RequestM`, `withWaitFindSnap`, etc.).
- Already uses infotrees for tactics (`goalsAt?` in `load_node`).

Implications:
- We can implement hover/goal/term-goal directly from infotrees.
- We should adapt LSP logic to static context (no async snapshot search).
- To better mirror LSP hover fallback, we should enrich context slightly.

---

## 3) Proposed API additions

### 3.1 File worker methods (new)

1. `get_hover`
   - params: `{ line, col }`
   - result: `Option { text : String, range? : ... }`

2. `get_plain_goal`
   - params: `{ line, col }`
   - result: `Option { goals : List String, rendered : String }`
   - `rendered` will be plain-text rendering (no HTML/JS).

3. `get_plain_term_goal`
   - params: `{ line, col }`
   - result: `Option { goal : String, range? : ... }`

Optional (convenience):
4. `get_infoview`
   - params: `{ line, col }`
   - result: `{ hover? : ..., plainGoal? : ..., plainTermGoal? : ... }`

### 3.2 Hub methods (new)
Same method names, but file-scoped params:
- `{ path, line, col }`.

### 3.3 Pi extension tools (new)
- `aftk_get_hover`
- `aftk_get_plain_goal`
- `aftk_get_plain_term_goal`
- (optional) `aftk_get_infoview`

All tools return text content + structured `details`.

---

## 4) File worker implementation plan

### 4.1 Context updates
Update `AFTK.FileWorker.Context` to include data useful for LSP-like selection/fallback:

- `env : Environment` (for parser docstring lookup).
- `commandTrees : Array (Syntax × InfoTree)` (or equivalent struct), extracted once at startup.

Keep existing fields:
- `inputCtx`
- `infoTrees`

### 4.2 Shared helpers
Add helper layer in `AFTK/FileWorker.lean`:

1. Position helper
- Convert `(line,col)` to raw pos.
- Validate line/col >= 1 (return `invalidParams` on bad input).

2. Command selection helper
- Given raw pos, choose relevant command infotree(s) by command syntax range.
- This replaces snapshot search used in LSP.

3. Hover helper
- Run `hoverableInfoAtM?` on selected infotree.
- Build hover text via `Info.fmtHover?`.
- Add parser-docstring fallback using command syntax stack + `findDocString?`.
- LSP-like precedence: prefer infotree hover when specific enough.

4. Plain goal helper
- Use `InfoTree.goalsAt?` at position.
- Reconstruct proper mctx (`before`/`after` depending on `useAfter`).
- Pretty-print each goal to plain string.
- Build `rendered` as plain-text block separator (not HTML/JS).

5. Plain term goal helper
- Use `InfoTree.termGoalAt?`.
- For `TermInfo`, compute expected type in context.
- Pretty-print as plain goal string + optional range.

### 4.3 Register handlers
Add handlers in `server.handlers` for the new methods.

Keep existing methods (`load_node`, `get_goals`, `run_tactic`) unchanged.

---

## 5) Hub server wiring plan (`AFTK/Server.lean`)

1. Add new param/result structures (derive `FromJson`/`ToJson`).
2. Add forwarding handlers:
   - canonicalize path
   - construct worker params `{ line, col }`
   - `forwardToWorker`
   - `decodeWorkerResult`
3. Register handlers in hub `server.handlers`.
4. Preserve existing session/file-stamp behavior unchanged.

---

## 6) Pi extension wiring plan (`.pi/extensions/aftk-hub.ts`)

1. Add TypeBox schemas for new tool params.
2. Add TS interfaces for new result types.
3. Register tools:
   - `aftk_get_hover`
   - `aftk_get_plain_goal`
   - `aftk_get_plain_term_goal`
   - optional `aftk_get_infoview`
4. Add text formatters:
   - hover: show text or "No hover info."
   - plain goal: numbered goals or "no goals"
   - term goal: goal text with range if present
5. Keep existing error conversion (`toErrorResult`) and truncation behavior.

---

## 7) Documentation updates

After implementation, update:

- `README.md`
  - file worker method list
  - hub API section with new methods + examples
- `.pi/extensions/README.md`
  - list of new tools

---

## 8) Validation plan

1. Build
- `lake build`

2. Direct worker JSON-RPC checks
- Query known positions in `Test.lean`:
  - tactic keyword hover (`rw`, `intro`, `exact`)
  - constant hover (`Nat.add_comm`)
  - tactic-state positions for plain goals
  - term positions for plain term goal
  - positions with no result -> `null`

3. Hub checks
- `open` -> new methods -> `close`
- Ensure path canonicalization + stale-worker behavior unchanged.

4. Pi extension checks
- New `aftk_*` tools return readable plain text and structured details.

---

## 9) Notes / decisions

- We intentionally target plain text outputs (no widget HTML/JS).
- Markdown markers from Lean hover formatting may still appear as plain text; if needed, add a later post-processing pass to strip markdown fences/emphasis.
- Because AFTK is static (non-incremental), behavior near whitespace may differ slightly from full LSP snapshot logic; command-range selection should minimize this gap.
