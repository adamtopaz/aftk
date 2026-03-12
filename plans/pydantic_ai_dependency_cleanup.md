# Plan: remove the "optional pydantic-ai" assumption from the existing AFTK toolkit

## Goal

Bring the existing `aftk.toolkits.aftk` implementation in line with the current project direction:

- we are building **Pydantic AI toolkits for Pydantic AI agents**
- we should stop treating `pydantic-ai` as an optional add-on for the toolkit layer
- the code and packaging should say that clearly

This is a cleanup/simplification pass, not a redesign of the toolkit itself.

---

## What I inspected

I looked at the current AFTK toolkit code and packaging:

- `aftk/toolkits/aftk/__init__.py`
- `aftk/toolkits/aftk/_toolkit.py`
- `aftk/toolkits/__init__.py`
- `pyproject.toml`
- `README.md`
- repository references to `optional 'pydantic-ai'`, `uv sync --extra pydantic-ai`, and related wording

---

## Findings

### 1. The toolkit implementation is already directly tied to Pydantic AI

`aftk/toolkits/aftk/_toolkit.py` imports Pydantic AI types directly:

- `CombinedToolset`
- `FunctionToolset`
- `WrapperToolset`

So the implementation itself is **already a Pydantic-AI-specific toolkit**, not a generic abstraction.

That means we do **not** need to redesign the actual toolkit logic.

### 2. The "optional" assumption currently exists at the package boundary

The current optional-dependency design shows up in these places:

1. `aftk/toolkits/aftk/__init__.py`
   - wraps the import in `try/except ModuleNotFoundError`
   - raises a custom message saying `pydantic-ai` is optional

2. `pyproject.toml`
   - keeps `pydantic-ai>=1,<2` under `[project.optional-dependencies]`
   - does **not** list it under the main project dependencies

3. `README.md`
   - has an "Optional Pydantic AI toolkit" section
   - tells users to install via `uv sync --extra pydantic-ai`

4. `aftk/toolkits/__init__.py`
   - says `"""Optional toolkit integrations for AFTK."""`

5. `plans/aftk_toolkit.md`
   - still documents the original optional-dependency decision

### 3. We likely do need to act

Yes.

Not because the toolkit implementation is broken, but because the current packaging/docs still
encode a design assumption we no longer want:

- that the Pydantic AI toolkit is an optional side integration

Given the current direction, the simplest consistent approach is:

- treat `pydantic-ai` as a normal dependency for this package
- remove the optional-import shim
- update docs to present the toolkit as first-class

### 4. The required code change surface is small

The good news is that this is mostly a packaging/import/docs cleanup.

The core implementation in:

- `aftk/toolkits/aftk/_toolkit.py`
- `aftk/toolkits/aftk/errors.py`
- `aftk/toolkits/aftk/models.py`

probably does **not** need any functional change for this cleanup.

---

## Decision

We should make the existing AFTK toolkit stop pretending that `pydantic-ai` is optional.

### Recommended interpretation

For this repository, the right simplification is:

- `pydantic-ai` becomes a **normal project dependency**
- `aftk.toolkits.aftk` imports it directly, without a custom missing-dependency wrapper
- docs stop advertising a separate extra just to use the toolkit

This is the cleanest way to match the current project direction.

---

## Proposed changes

### 1. Make `pydantic-ai` a normal dependency in `pyproject.toml`

Change packaging so that:

- `[project.dependencies]` includes `pydantic-ai>=1,<2`
- `[project.optional-dependencies].pydantic-ai` is removed
- the duplicate dev-only entry can be removed if no longer needed

Result:

- `uv sync` gives you the toolkit dependency by default
- there is no separate install path just for toolkit support

### 2. Remove the import guard from `aftk/toolkits/aftk/__init__.py`

Replace the current guarded import:

```python
try:
    from ._toolkit import AftkToolkit
except ModuleNotFoundError as exc:
    ...
```

with a direct import:

```python
from ._toolkit import AftkToolkit
```

Reason:

- once `pydantic-ai` is a normal dependency, the missing-dependency shim is unnecessary noise
- it also keeps the package surface honest: this is a Pydantic AI toolkit

### 3. Update toolkit-facing wording

Clean up wording that still reflects the old assumption.

Files to update:

- `aftk/toolkits/__init__.py`
- `README.md`
- `plans/aftk_toolkit.md`

Recommended wording changes:

- from "Optional toolkit integrations"
- to something like "Pydantic AI toolkits for AFTK" or simply "Toolkits for AFTK"

And in the README:

- remove the "Optional Pydantic AI toolkit" framing
- remove `uv sync --extra pydantic-ai`
- present toolkit usage as normal package functionality

### 4. Regenerate lockfile

After changing dependencies:

- update `uv.lock`

### 5. Validate imports and tests

Run the same Python validation we already use for toolkit work.

---

## What should *not* change

This cleanup should **not** trigger a broader redesign.

Specifically, we do **not** need to:

- rewrite `AftkToolkit`
- change its tool surface
- change its structured failure model
- split the toolkit into a separate distribution
- change the existing `AftkToolkit(...)` API

The implementation is already Pydantic-AI-specific; the cleanup is about making the packaging and
messaging match that reality.

---

## Why this is the right scope

The important observation is:

- the current toolkit code already assumes Pydantic AI
- only the **import guard, dependency metadata, and docs** still act like this is an optional sidecar

So the cleanup should target exactly those pieces.

That gives us a simpler and more consistent package without unnecessary churn.

---

## Concrete edit list

### Files that should change

- `pyproject.toml`
- `uv.lock`
- `aftk/toolkits/aftk/__init__.py`
- `aftk/toolkits/__init__.py`
- `README.md`
- `plans/aftk_toolkit.md`

### Files that probably do not need changes

- `aftk/toolkits/aftk/_toolkit.py`
- `aftk/toolkits/aftk/errors.py`
- `aftk/toolkits/aftk/models.py`
- `tests/python/test_pydantic_ai_toolkit.py` (unless wording/import expectations change)

---

## Validation plan

After making the cleanup:

```bash
uv run python -m unittest tests.python.test_pydantic_ai_toolkit -v
uv run python -m unittest discover -s tests/python -v
uv run ruff check aftk tests/python/test_pydantic_ai_toolkit.py
uv run pyright
```

Also add a simple import smoke test:

```bash
uv run python - <<'PY'
from aftk.toolkits.aftk import AftkToolkit
print(AftkToolkit.__name__)
PY
```

---

## Recommendation

Yes, we should act.

But the fix should be **small and surgical**:

1. make `pydantic-ai` a regular dependency
2. remove the optional-import wrapper
3. clean up docs/wording
4. leave the actual toolkit implementation alone

That is enough to bring the existing AFTK toolkit into line with the direction we now want.
