# Toolkit testing

The TypeScript toolkit has its own package-level test workflow.
It is separate from the Lean-only `lake test` driver.

Run the toolkit typecheck:

```text
npm run check
```

Run toolkit unit tests only:

```text
npm run test:toolkit:unit
```

Run toolkit integration tests only:

```text
npm run test:toolkit:integration
```

Run the full toolkit suite:

```text
npm run test:toolkit
```

Run both Lean-layer and toolkit-layer tests:

```text
npm run test:all
```

## Runner model

The toolkit tests use the Node test runner with TypeScript stripping enabled:

```text
node --experimental-strip-types --test ...
```

This is wired through `package.json` scripts rather than through Lake.

## Test layout

Toolkit tests live under `tests/toolkit/`:

```text
tests/toolkit/support/helpers.ts
tests/toolkit/runtime/project-root.unit.test.ts
tests/toolkit/output/truncate.unit.test.ts
tests/toolkit/server/client.unit.test.ts
tests/toolkit/server/client.integration.test.ts
tests/toolkit/tools/lean.integration.test.ts
tests/toolkit/knowledgebase/tools.integration.test.ts
tests/toolkit/informal/tools.integration.test.ts
tests/toolkit/hosts/pi.unit.test.ts
```

Toolkit-owned process fixtures currently live under:

```text
tests/toolkit/fixtures/process/
```

The current synthetic fixture is:

```text
tests/toolkit/fixtures/process/malformed-jsonrpc.mjs
```

## Current coverage

### Runtime helper tests

`tests/toolkit/runtime/project-root.unit.test.ts` covers:

- upward project-root discovery from a nested toolkit test directory
- rejection when no Lean project root can be found

### Output tests

`tests/toolkit/output/truncate.unit.test.ts` covers:

- preserving short text unchanged
- explicit truncation metadata and truncation notices for oversized text

### Managed server-client tests

`tests/toolkit/server/client.unit.test.ts` covers:

- protocol-corruption handling when hub stdout is malformed JSON-RPC

`tests/toolkit/server/client.integration.test.ts` covers, against a real `aftk_server` subprocess:

- opening a real Lean file
- ordinary hover lookup
- loading tactic-state nodes
- goal lookup from a node id
- graceful server shutdown and running-state cleanup

### Lean-tool-family tests

`tests/toolkit/tools/lean.integration.test.ts` covers:

- the exact exported `aftk_*` tool-name surface
- path normalization with leading `@`
- failure before opening a file
- real richer hover at an `informal[...]` site after opening the file
- `load_node` + `run_tactic` over the real server surface
- managed toolset shutdown

### Knowledge-base-tool tests

`tests/toolkit/knowledgebase/tools.integration.test.ts` covers:

- the exact initial `knowledgebase_*` tool-name surface
- real CLI-backed status and text-search queries
- validation-report success semantics on an invalid root
- preservation of backend metadata such as CLI exit code `4` on validation reports

### Informal-tool tests

`tests/toolkit/informal/tools.integration.test.ts` covers:

- the exact initial `informal_*` tool-name surface
- real CLI-backed status queries
- reference-dependency rendering
- rich presentation preview mode and explicit body truncation metadata

### Pi-adapter tests

`tests/toolkit/hosts/pi.unit.test.ts` covers:

- extension-style registration of toolkit tools into a pi-like API
- registration of the `aftk-extension-stop` command
- session-shutdown cleanup wiring
- disposal behavior after explicit stop and shutdown-hook invocation

## Fixture reuse

The toolkit integration tests intentionally reuse existing repository fixtures where the Lean layers already define the truth.

### Reused server fixtures

The toolkit server and Lean-tool tests use:

```text
tests/server/fixtures/lean/Semantics.lean
tests/server/fixtures/lean/Informal.lean
```

These cover:

- ordinary hover
- goal/term-goal/tactic-node behavior
- richer hover for `informal[...]`

### Reused knowledge-base / informal fixtures

The toolkit knowledge-base and informal tests use roots under:

```text
tests/informal/knowledgebase-fixtures/
```

Important roots currently exercised:

- `basic-valid`
- `malformed-node`
- `long-body`

These cover:

- successful status/search/presentation flows
- malformed metadata / validation-report behavior
- preview-body truncation behavior

### Toolkit-owned synthetic fixture

`tests/toolkit/fixtures/process/malformed-jsonrpc.mjs` emits invalid JSON on stdout and then stays alive.
This fixture exists specifically to test the toolkit's protocol-corruption handling independently of the real Lean server.

## What the tests intentionally enforce

A few toolkit behaviors are treated as important compatibility boundaries:

- runtime project-root discovery uses `lakefile.toml` / `lakefile.lean`
- rendered output truncation is explicit rather than silent
- malformed managed-process stdout is treated as protocol failure
- the managed `aftk_server` client can talk to the real public hub protocol
- the Lean tool family preserves the expected `aftk_*` surface
- the knowledge-base tool family keeps validation reports as semantic success results
- the informal tool family preserves preview truncation metadata
- the pi adapter stays thin and lifecycle-aware

## Why the TypeScript tests are separate from `lake test`

The toolkit owns behavior that the Lean test suites do not cover directly:

- Node-side project-root resolution
- subprocess management from TypeScript
- JSON parsing and normalization of lower-layer outputs
- host-facing result envelopes
- pi-adapter lifecycle wiring

Those are real package-level contracts, so they are tested through Node rather than being forced into the Lean test driver.

## Good extension rule

When you change the toolkit layer, prefer this order:

1. add/update a small unit test if the change is in runtime or output helpers
2. add/update a synthetic process test if protocol/lifecycle behavior changes
3. add/update a real integration test if a lower-layer boundary or tool-family contract changes
4. add/update pi-adapter tests if host registration or cleanup behavior changes

## Current limitations reflected by the tests

The current toolkit suite is intentionally focused on implemented boundaries.
It does **not** try to duplicate the full Lean semantic coverage already owned by:

- `AFTKTest/KnowledgeBase/`
- `AFTKTest/Informal/`
- `AFTKTest/Server/`

It also does not yet include:

- broad unit coverage for every renderer and parser helper
- mutation-command coverage for knowledge-base tools, because those commands are still deferred from the toolkit surface
- full end-to-end AI-agent workflow tests, because the AI layer does not exist yet

So the toolkit tests are best understood as boundary and contract tests for the implemented TypeScript layer, not as a replacement for the Lean-layer suites.
