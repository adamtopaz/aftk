# Plan: add a simple one-turn agent runner in `main.py`

## Goal

Create a root-level `main.py` entrypoint that runs **one full Pydantic AI agent turn** using the
new coding toolkit, with:

- a hard-coded default model of `gpt-5.4-pro`
- customizable thinking level
- a stub developer prompt stored directly in `main.py`
- a simple final output type of `str`
- one call to the agent that allows the model to think, call tools, receive tool results, call
  more tools if needed, and finally return a string response

---

## What I inspected

I read the relevant Pydantic AI docs from `https://ai.pydantic.dev/llms.txt` and the linked pages:

- Agents: https://ai.pydantic.dev/agent/
- Toolsets: https://ai.pydantic.dev/toolsets/
- Output: https://ai.pydantic.dev/output/
- Thinking: https://ai.pydantic.dev/thinking/
- OpenAI models: https://ai.pydantic.dev/models/openai/
- OpenAI model API reference: https://ai.pydantic.dev/api/models/openai/
- Model settings: https://ai.pydantic.dev/api/settings/

I also checked the repository layout and confirmed that there is **currently no root `main.py`**,
so this implementation will need to create it rather than edit an existing file.

---

## Findings

### 1. `agent.run(...)` is the right primitive for a full single-turn agent loop

Per the Agents docs, `agent.run(...)` is the normal async API that executes the agent graph to
completion and returns a final `RunResult`.

That matches the requested behavior:

- model receives developer instructions / system guidance
- model sees the available tools
- model can call tools repeatedly
- tool results are fed back into the run
- model eventually returns final output

For this use case, we should prefer:

```python
result = await agent.run(user_prompt, ...)
return result.output
```

Relevant docs:
- https://ai.pydantic.dev/agent/#running-agents

### 2. We should avoid `run_stream()` for the first implementation

The Agents docs explicitly note that with `run_stream()` and a text output type, a text response can
be treated as final before later tool calls are executed. That is not what we want here.

Because the request is for **one full turn** that runs all needed tool calls before finishing,
plain `await agent.run(...)` is the safest and simplest choice.

Relevant docs:
- https://ai.pydantic.dev/agent/#streaming-events-and-final-output

### 3. Toolsets fit this use case directly

Pydantic AI supports reusable toolsets passed either:

- when constructing the `Agent`, or
- at run time via `agent.run(..., toolsets=[...])`

Since this entrypoint is supposed to be a simple local agent runner, the cleanest first version is
probably to build the agent with a `CodingToolkit` attached up front.

Relevant docs:
- https://ai.pydantic.dev/toolsets/

### 4. A final output type of `str` is fine

The Output docs say that if no output type is specified, or if `str` is included, a plain text
response can be used as the final output.

Because the user explicitly wants a simple string result for now, we should use:

```python
output_type=str
```

This keeps the code explicit and makes `result.output` clearly typed as a string.

Relevant docs:
- https://ai.pydantic.dev/output/

### 5. For customizable thinking with OpenAI, the best fit is `OpenAIResponsesModel`

The Thinking docs say that for OpenAI's Responses API, native reasoning is enabled through:

- `OpenAIResponsesModelSettings.openai_reasoning_effort`
- `OpenAIResponsesModelSettings.openai_reasoning_summary`

The OpenAI docs also show that Pydantic AI supports the shorthand:

```python
Agent('openai-responses:gpt-5.2')
```

So for this implementation, the best default is:

- use the **Responses API** model path
- default model name constant to `gpt-5.4-pro`
- construct an `OpenAIResponsesModel`
- pass `OpenAIResponsesModelSettings` with a configurable `openai_reasoning_effort`

That gives us the most direct, documented way to expose a user-controlled thinking level.

Relevant docs:
- https://ai.pydantic.dev/thinking/#openai
- https://ai.pydantic.dev/models/openai/#openai-responses-api
- https://ai.pydantic.dev/api/models/openai/

### 6. Pydantic AI recommends `instructions` over `system_prompt`

The Agents docs recommend using `instructions` instead of `system_prompt` for most use cases.
However, the requested UX is explicitly framed as “system prompt + user prompt”.

So there are two reasonable options:

1. **Recommended implementation choice:**
   keep a constant named `SYSTEM_PROMPT` in `main.py`, but pass it to the agent via
   `instructions=SYSTEM_PROMPT`
2. **Literal implementation choice:**
   pass the stub via `system_prompt=SYSTEM_PROMPT`

Because this is a one-turn local runner with no message-history requirements, either will work.
My recommendation is option 1, since it follows the docs while preserving the naming the user wants
inside `main.py`.

Relevant docs:
- https://ai.pydantic.dev/agent/#instructions
- https://ai.pydantic.dev/agent/#system-prompts

### 7. Thinking level should map to OpenAI reasoning effort

The documented OpenAI reasoning effort values are:

- `low`
- `medium`
- `high`

So the simplest public configuration surface in `main.py` is a literal type or alias around those
three values.

Relevant docs:
- https://ai.pydantic.dev/thinking/#openai
- https://ai.pydantic.dev/api/models/openai/

---

## Recommended implementation shape

### File to create

- `main.py`

### Constants to define in `main.py`

At minimum:

```python
DEFAULT_MODEL_NAME = "gpt-5.4-pro"
DEFAULT_THINKING_LEVEL = "medium"
SYSTEM_PROMPT = """TODO: replace this stub prompt."""
USER_PROMPT = "TODO: replace this stub user prompt."
```

I recommend also defining the provider/model route explicitly, e.g. either:

```python
DEFAULT_MODEL_NAME = "gpt-5.4-pro"
```

and then constructing:

```python
OpenAIResponsesModel(DEFAULT_MODEL_NAME)
```

or storing the full routed model string separately if we decide to use shorthand at the `Agent`
level.

### Type alias for thinking level

Use a narrow type for clarity:

```python
ThinkingLevel = Literal["low", "medium", "high"]
```

### Helper functions

I recommend three small helpers:

1. `build_model(model_name: str) -> OpenAIResponsesModel`
2. `build_model_settings(thinking_level: ThinkingLevel) -> OpenAIResponsesModelSettings`
3. `build_agent(...) -> Agent[None, str]`

This keeps `main()` small and makes the configuration logic obvious.

### Agent construction

Recommended shape:

- `output_type=str`
- attach `CodingToolkit(cwd=Path.cwd(), include_search=True)`
- supply static instructions / prompt stub from a constant
- use `OpenAIResponsesModel`
- use `OpenAIResponsesModelSettings` for reasoning effort

### Main function behavior

The async `main()` should perform exactly one run:

1. build model
2. build model settings from the requested thinking level
3. build the agent with the coding toolkit
4. call `await agent.run(USER_PROMPT, model_settings=...)`
5. return `result.output`

A small synchronous module entrypoint can then call `asyncio.run(main())` and print the returned
string.

---

## Concrete plan

### Phase 1: create the entrypoint skeleton

Create a new root `main.py` containing:

- imports
- default model constant
- default thinking-level constant
- stub prompt constants
- typing alias for reasoning effort

### Phase 2: wire OpenAI Responses model configuration

Use:

- `OpenAIResponsesModel`
- `OpenAIResponsesModelSettings`

Set at least:

- `openai_reasoning_effort=thinking_level`

Optionally set:

- `openai_reasoning_summary="auto"` or `"detailed"`

For the first pass, `"auto"` is probably the least opinionated default, while still preserving a
clear place to tune this later.

### Phase 3: attach the coding tools

Construct a `CodingToolkit` rooted at the current working directory:

```python
CodingToolkit(cwd=Path.cwd(), include_search=True)
```

and pass it to the agent.

For the first version, keep the tool surface simple:

- full coding toolkit
- no separate AFTK client/toolkit wiring yet

### Phase 4: run one full turn

Use:

```python
result = await agent.run(USER_PROMPT, model_settings=model_settings)
```

This is the core of the requested behavior: a single full run that may involve multiple internal
model/tool iterations before producing final text.

### Phase 5: add a simple module entrypoint

At the bottom of `main.py`:

```python
if __name__ == "__main__":
    print(asyncio.run(main()))
```

This keeps the file executable with:

```bash
uv run python main.py
```

---

## Suggested exact implementation choices

### Model choice

Recommended:

- `OpenAIResponsesModel`
- default model name constant: `"gpt-5.4-pro"`

### Prompt plumbing

Recommended:

- keep `SYSTEM_PROMPT` as a visible stub constant in `main.py`
- use it via `instructions=SYSTEM_PROMPT`
- keep `USER_PROMPT` as a second stub constant for quick editing

This best matches the user request while staying aligned with the Pydantic guidance that
`instructions` is usually preferred.

### Thinking-level plumbing

Recommended API:

```python
async def main(
    user_prompt: str = USER_PROMPT,
    *,
    model_name: str = DEFAULT_MODEL_NAME,
    thinking_level: ThinkingLevel = DEFAULT_THINKING_LEVEL,
) -> str:
    ...
```

That satisfies “model configurable with gpt-5.4-pro as a default” and “thinking level
customizable” without adding unnecessary CLI complexity yet.

---

## Validation plan after implementation

Once implemented, validate with:

- `uv run python -m pyright`
- `uv run ruff check main.py aftk tests/python`
- `uv run python main.py`

If we decide to add a focused test file later, we can also add a small construction test that checks
that:

- the agent builds successfully
- the default model constant is used
- the model settings carry the requested reasoning effort

---

## Non-goals for this first pass

Do **not** add all of these yet:

- multi-turn chat history persistence
- streaming UI
- combined `AftkToolkit + CodingToolkit` orchestration
- rich CLI argument parsing
- environment-variable configuration layers beyond the normal OpenAI API key handling
- structured output beyond `str`

Those can come later once the single-turn runner works cleanly.

---

## Summary

The implementation should:

- create a new root `main.py`
- use `OpenAIResponsesModel` with default model name `gpt-5.4-pro`
- expose `low` / `medium` / `high` thinking-level control via
  `OpenAIResponsesModelSettings.openai_reasoning_effort`
- attach `CodingToolkit`
- keep prompt stubs directly in `main.py`
- run exactly one full agent turn with `await agent.run(...)`
- return a plain string response

This is the smallest implementation that matches the requested behavior and is well aligned with the
current Pydantic AI documentation.
