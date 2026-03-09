# Toolkit Testing Design

## Status

Component design/status document for testing the TypeScript toolkit layer.
This file now records the rationale for the toolkit test strategy that exists in code and the follow-on work that may still be added later.

Authoritative implementation docs live in:

- `docs/toolkit/testing.md`
- `docs/toolkit/library.md`
- `docs/toolkit/overview.md`

## Component implementation status

- Overall status: Implemented (initial v1), with deferred follow-ons
- Implemented in code: Yes
- Last updated basis: the current TypeScript-side test suite under `tests/toolkit/**`, package scripts in `package.json`, and the current runtime/server-client/tool-family implementations
- Main deferred follow-ons: broader mutation/admin integration coverage if the toolkit surface expands, plus any future higher-level end-to-end AI-layer tests

The test-strategy questions this file was written to settle are now answered by the current repository layout and scripts.
Historical sections below may still describe the earlier pre-implementation gap; read them as design rationale only.

## Purpose

This document defines how the rewrite toolkit layer should be tested.
It covers:

- TypeScript-side unit tests for pure helpers
- synthetic-process tests for runtime edge cases
- real subprocess integration tests for:
  - `lake exe aftk_server`
  - `lake exe aftk knowledgebase ...`
  - `lake exe aftk informal ...`
- tool-family tests above those lower-layer clients
- host-adapter tests for pi mounting
- temporary-fixture policy for mutable scenarios
- and how toolkit tests should fit into the repository’s broader workflows

The goal is to make testing part of the toolkit architecture from the beginning instead of repeating the main-worktree pattern where the TypeScript side remained largely untested and operational behavior lived mostly in one file.

## Design goals

Toolkit testing should:

- validate reusable TypeScript behavior below the host adapters
- validate the real subprocess boundaries that the toolkit exists to manage
- focus on toolkit-owned contracts rather than duplicating every lower-layer semantic test already covered in Lean
- cover lazy startup, timeout, cancellation, stderr capture, malformed output, and shutdown behavior explicitly
- reuse the repository’s existing Lean/knowledge-base/informal fixtures where possible
- keep checked-in fixtures immutable during test runs
- support a future safe mutation-test story even though v1 knowledge-base tools are query/report-first
- fit cleanly beside the existing `lake test` workflow without trying to hide TypeScript tests inside it
- remain deterministic enough for frequent local use
- avoid requiring network access, model API keys, or interactive pi UI for ordinary toolkit tests

## Scope and non-scope

### In scope

- test-runner and workflow strategy for TypeScript toolkit tests
- test-tree layout under `tests/toolkit/`
- toolkit-owned support helpers for subprocesses, temp fixtures, and host-adapter spies
- synthetic-process fixtures for operational edge cases
- real lower-layer subprocess coverage for server, knowledge-base CLI, and informal CLI integration
- tool-family contract tests
- pi adapter tests where practical
- policy for mutable test scenarios and future mutation tools

### Out of scope

- continuous-integration service configuration details
- benchmarking or performance suites
- exhaustive duplication of server/informal/knowledge-base semantic coverage already owned by the Lean-layer suites
- full end-to-end LLM prompting behavior through pi sessions
- remote or multi-machine integration testing

## Research basis and design consequences

This testing plan is based on explicit research in both worktrees and in the pi SDK docs/examples.

### Main-worktree reference points

Primary files studied:

- `../aftk/package.json`
- `../aftk/tsconfig.json`
- `../aftk/lambda/src/aftk-extension.ts`
- `../aftk/lambda/src/aftk-tools.ts`

Important observations:

- The current main-worktree package only advertises a typecheck script:
  - `check: bunx tsc --noEmit`
- There is no real TypeScript-side toolkit test suite in the main worktree.
- The toolkit implementation is concentrated in one TypeScript file plus a thin pi wrapper.
- The pi wrapper itself is simple enough that the missing coverage matters less for pure wiring than for operational behavior such as subprocess lifecycle and error mapping.

Main consequences for the rewrite:

- AFTK should add a deliberate TypeScript-side test suite rather than inheriting the historical absence of one;
- AFTK should test runtime/process behavior and normalization contracts directly;
- and AFTK should not treat typechecking alone as adequate toolkit validation.

### Repository reference points

Primary files studied:

- `README.md`
- `docs/architecture.md`
- `lakefile.lean`
- `package.json`
- `tsconfig.json`
- `plans/toolkit.md`
- `plans/toolkit/layout.md`
- `plans/toolkit/runtime.md`
- `plans/toolkit/server-client.md`
- `plans/toolkit/output.md`
- `plans/toolkit/lean-tools.md`
- `plans/toolkit/knowledgebase-tools.md`
- `plans/toolkit/informal-tools.md`
- `plans/toolkit/pi-integration.md`
- `plans/server/testing.md`

Important observations:

- The repository already has a strong Lean-layer testing culture centered on:

```text
lake test
```

  with suite executables under `AFTKTest/` and checked-in fixtures under `tests/`.
- The current repository test fixtures already include reusable inputs for toolkit integration:
  - `tests/server/fixtures/lean/`
  - `tests/server/fixtures/knowledgebase/`
  - `tests/informal/knowledgebase-fixtures/`
  - `AFTKTest/Informal/Fixtures/*`
- `lakefile.lean` fixes the exact executable names that real toolkit integration tests target:
  - `aftk_server`
  - `aftk`
  - `aftk_file_worker`
- `AFTK/Server/Main.lean` currently accepts no extra CLI flags and always uses stdio transport, which keeps the server-side integration harness simple.
- The original pre-toolkit `package.json` and `tsconfig.json` were still Bun-style scaffolding and did not yet describe a real TypeScript test workflow.
  Concretely, the package still points `module` at the root `index.ts`, while `tsconfig.json` still uses Bun-oriented `module: "Preserve"` / `moduleResolution: "bundler"` defaults.
- `plans/toolkit/layout.md` has already settled that toolkit test code belongs under:

```text
tests/toolkit/
```

- The runtime, server-client, output, tool-family, and pi-integration plans already settle many toolkit-side contracts that must be tested explicitly, including:
  - strict project-root discovery
  - Node-compatible subprocess behavior
  - lazy managed hub startup
  - timeout vs cancellation distinctions
  - malformed non-empty server stdout as protocol failure
  - capture-first stderr policy
  - normalized success/failure envelopes
  - exact Lean-family `aftk_*` naming
  - query/report-first knowledge-base and informal families
  - and thin pi-specific host adapters
- The current lower-layer implementations also make several concrete parser/test targets explicit:
  - knowledge-base JSON uses exact dot-separated command identifiers such as `validate.storage` and `relationships.related`;
  - knowledge-base validation returns a semantic report even when the CLI exits `4`;
  - informal success JSON is command-shaped around `data`, `target`, `mode`, and `bodyMode`;
  - informal tracking/dependency/presentation outputs are already deterministically sorted;
  - and `informal present` preview mode already carries structured truncation metadata.

Main consequences for the rewrite:

- toolkit tests should live beside the Lean suites, not inside them;
- toolkit tests should reuse existing repository fixtures instead of creating a second duplicate fixture universe;
- `lake test` should remain the canonical Lean-layer entrypoint, while toolkit tests get their own explicit package-level workflow;
- and toolkit tests must cover the toolkit-owned contracts, not only the lower-layer semantics.

### Pi SDK and extension reference points

Primary docs/examples studied:

- `/home/dev/.nvm/versions/node/v25.5.0/lib/node_modules/@mariozechner/pi-coding-agent/docs/extensions.md`
- `/home/dev/.nvm/versions/node/v25.5.0/lib/node_modules/@mariozechner/pi-coding-agent/docs/sdk.md`
- `/home/dev/.nvm/versions/node/v25.5.0/lib/node_modules/@mariozechner/pi-coding-agent/examples/sdk/05-tools.ts`
- `/home/dev/.nvm/versions/node/v25.5.0/lib/node_modules/@mariozechner/pi-coding-agent/examples/sdk/06-extensions.ts`

Important observations:

- pi custom tools and extension registration can be exercised programmatically.
- The documented SDK surfaces include:
  - `createAgentSession(...)`
  - `DefaultResourceLoader`
  - `additionalExtensionPaths`
  - `extensionFactories`
- Extension behavior centers on tool registration, commands, and lifecycle hooks such as `session_shutdown`.

Main consequences for the rewrite:

- the host-adapter layer can be tested without an interactive TUI;
- direct tool-definition execution and extension-registration spies should provide most coverage;
- and a small number of SDK-level smoke tests may be added where practical, but ordinary toolkit tests should not require real model calls or network access.

## Core testing decisions

The v1 toolkit testing design should make the following decisions explicit.

### 1. Keep TypeScript toolkit tests separate from `lake test`

The repository should preserve the existing meaning of:

```text
lake test
```

as the Lean-layer aggregate test driver.

Toolkit tests should run through a separate package-level workflow rather than being forced into Lake.

Reasoning:

- the toolkit layer is TypeScript, not Lean;
- its test runner and process model differ;
- and keeping the workflows separate makes failures easier to interpret.

This does **not** make toolkit tests second-class.
It just means they should be first-class in the right place.

### 2. Add a dedicated package-level toolkit test workflow

AFTK should add explicit package scripts for toolkit validation.
A good v1 shape is:

- `check` — TypeScript typecheck
- `test:toolkit:unit` — pure and synthetic-process tests
- `test:toolkit:integration` — real lower-layer subprocess tests
- `test:toolkit` — all toolkit tests
- `test:all` — full repository check combining `lake test` and toolkit tests

The exact command spelling can be finalized during implementation, but the workflow separation should be deliberate.

### 3. Use the Node-native test API, not a Bun-specific test runner

Because the runtime design is explicitly Node-compatible, the test surface should follow that same assumption.

A good v1 choice is:

- `node:test` for the test API
- `node:assert/strict` for assertions
- `tsx` or an equivalently lightweight loader for executing `.ts` test files without a build step

Conceptually, the execution model should look like:

```text
node --import tsx --test ...
```

This keeps the test environment aligned with the runtime assumptions of the toolkit itself.

### 4. Split fast/synthetic tests from real integration tests

Toolkit testing should have at least two clearly distinct layers.

#### Fast/synthetic tests

These include:

- pure helper tests
- output normalization tests
- argument-building tests
- fake-client tests
- synthetic child-process tests using small local fixture scripts

These should be the first choice during tight iteration.

#### Real integration tests

These include real subprocess tests against:

- `lake exe aftk_server`
- `lake exe aftk knowledgebase ...`
- `lake exe aftk informal ...`

These are essential because subprocess boundaries and machine-output parsing are part of the toolkit’s public behavior.

### 5. Reuse existing repository fixtures whenever they already represent the lower-layer truth

Toolkit tests should reuse existing checked-in repository fixtures such as:

- `tests/server/fixtures/lean/Informal.lean`
- `tests/server/fixtures/lean/Semantics.lean`
- `tests/server/fixtures/knowledgebase/basic-valid/`
- `tests/informal/knowledgebase-fixtures/basic-valid/`
- `tests/informal/knowledgebase-fixtures/long-body/`
- `AFTKTest.Informal.Fixtures.Basic`
- `AFTKTest.Informal.Fixtures.Imports.Top`

This avoids duplicate fixture maintenance and keeps the lower-layer truth in one place.

### 6. Add toolkit-owned synthetic process fixtures for hard operational cases

Some runtime and client behaviors are difficult or undesirable to provoke using the real Lean executables alone.
Examples include:

- malformed stdout lines
- stderr floods
- hangs and timeouts
- cancellation during output
- a child that ignores `SIGTERM`

So the toolkit test tree should include small toolkit-owned synthetic fixtures, likely under something like:

```text
tests/toolkit/fixtures/process/
```

These should be tiny Node scripts or similarly simple helpers that produce controlled behaviors for runtime tests.

### 7. Prefer structural assertions for machine-facing details

The toolkit’s strongest host-facing compatibility contract is the structured `details` payload, not the exact prose of the human-facing text.

So tests should strongly assert:

- normalized success/failure envelope shape
- backend metadata
- error kind/category/code preservation
- counts, ids, flags, warnings, and truncation metadata

Text should still be tested, but usually with focused assertions such as:

- expected key phrase exists
- known error renderer is actionable
- truncation marker is present

rather than fragile full-string goldens.

### 8. Use exact-output goldens only for toolkit-owned rendering where exact text is actually a contract

Goldens are still useful in selected places, but only for toolkit-owned stable output such as:

- representative normalized error text renderings
- truncation marker formatting
- stable summary formatting for one or two representative result renderers

They should **not** be the main mechanism for:

- Lean hover text across every case
- raw CLI JSON envelopes already tested structurally
- version-sensitive pretty-printed proof-state details

### 9. Do not mutate checked-in fixtures in place

No toolkit test should write into checked-in fixture trees.

Any scenario requiring mutation must operate on a per-test temporary copy.
This applies to:

- future knowledge-base mutation tools
- server/file invalidation tests that edit Lean files
- any workflow that changes manifests, node files, or metadata files on disk

### 10. Treat timeout, cancellation, cleanup, and restart behavior as first-class test targets

These are not incidental runtime details.
They are part of the toolkit contract.

Tests must therefore cover behavior such as:

- timeout vs cancellation distinction
- local cleanup after cancelled managed requests
- bounded stderr capture
- graceful shutdown vs forced termination fallback
- idempotent cleanup
- lazy restart after explicit stop when applicable

### 11. Do not try to duplicate all lower-layer semantic coverage in TypeScript

The Lean suites already own the deepest semantic tests for:

- knowledge-base validation/search semantics
- informal elaboration/tracking/dependency semantics
- server worker/hub semantics

Toolkit tests should focus on:

- invoking those lower layers correctly
- parsing their machine outputs correctly
- normalizing results correctly
- presenting and preserving errors correctly
- and respecting lifecycle/configuration policies correctly

Representative end-to-end coverage is necessary.
Exhaustive semantic duplication is not.

## Recommended test matrix

A good v1 coverage matrix is:

| Area | Fast/synthetic coverage | Real integration coverage | Primary assertions |
| --- | --- | --- | --- |
| Runtime helpers | Pure helpers + synthetic child fixtures | Minimal real `lake` smoke where helpful | root discovery, timeouts, cancellation, stderr capture, escalation |
| Output normalization | Pure tests | none required beyond representative tool-family checks | normalized envelopes, truncation, error mapping, text rendering |
| Server client | Fake/stdout-line protocol tests | `lake exe aftk_server` | lazy start, envelope validation, protocol failure, typed error codes, shutdown vs stop |
| Lean tools | Stub-client tests | representative real hub-backed tool calls | exact tool names, explicit lifecycle, path handling, details preservation |
| Knowledge-base bridge/tools | argv/parser tests | `lake exe aftk knowledgebase ...` | command mapping, JSON parsing, validation exit-code-4 special case |
| Informal bridge/tools | argv/parser tests | `lake exe aftk informal ...` | repeated `--module`, present semantics, JSON parsing, failure mapping |
| pi integration | adapter spies/direct tool execution | optional SDK smoke tests where practical | registration, stop command, `session_shutdown` cleanup, disposal |

## Recommended test tree

A practical initial TypeScript test tree is:

```text
tests/toolkit/
  support/
    fixtures.ts
    temp.ts
    lake.ts
    process.ts
    server.ts
    results.ts
    pi.ts
  fixtures/
    process/
      emit-json.mjs
      malformed-stdout.mjs
      stderr-flood.mjs
      hang.mjs
      ignore-sigterm.mjs
  runtime/
    *.unit.test.ts
    *.integration.test.ts
  output/
    *.unit.test.ts
  server/
    *.unit.test.ts
    *.integration.test.ts
  knowledgebase/
    *.unit.test.ts
    *.integration.test.ts
  informal/
    *.unit.test.ts
    *.integration.test.ts
  tools/
    *.unit.test.ts
    *.integration.test.ts
  hosts/
    *.unit.test.ts
    *.integration.test.ts
  golden/
    ... only when exact toolkit-owned text is intentionally stable ...
```

This extends the layout already settled in `plans/toolkit/layout.md` by adding:

- `support/` for test-only helpers
- `fixtures/process/` for synthetic subprocess behaviors
- `golden/` only for selective exact-output checks

## Runner and workflow strategy

### TypeScript-side runner choice

The toolkit test workflow should be based on:

- Node’s built-in test runner
- TypeScript source execution via a lightweight loader
- package scripts rather than ad hoc one-off commands

This keeps the tests aligned with the toolkit’s runtime assumptions:

- ESM
- Node-compatible subprocess APIs
- no required build output step for running tests

### Script strategy

A good conceptual package-script set is:

```json
{
  "scripts": {
    "check": "tsc --noEmit",
    "test:toolkit:unit": "node --import tsx --test tests/toolkit/**/*.unit.test.ts",
    "test:toolkit:integration": "node --import tsx --test tests/toolkit/**/*.integration.test.ts",
    "test:toolkit": "npm run test:toolkit:unit && npm run test:toolkit:integration",
    "test:all": "lake test && npm run test:toolkit"
  }
}
```

The exact package-manager spelling can vary, but the conceptual workflow should remain:

- Lean tests stay under `lake test`
- toolkit tests stay under package scripts
- a full-repository convenience command composes both

### Build strategy for real lower-layer tests

Real toolkit integration tests will often invoke `lake exe ...` commands.
That implies a buildable Lean environment.

A good operational policy is:

- integration tests may assume the repository has a working `lake` toolchain
- a shared helper may run `lake build` once per test process when helpful
- tests should not each trigger their own full cold build if a cached prebuild can avoid that

This is a practical test-performance concern, not a semantic contract.

### Parallelism policy

Pure and synthetic tests may run in parallel where convenient.
Real subprocess integration tests should begin conservatively.

A good v1 policy is:

- allow parallelism freely for pure tests
- prefer serial execution for suites that:
  - spawn real `lake` subprocesses repeatedly,
  - mutate temporary fixture copies,
  - or depend on controlled lifecycle timing
- only relax this after the suite is stable and timing behavior is well understood

Determinism matters more than maximal parallel throughput in v1.

## Test harness design

The toolkit suite does not need a heavy external framework.
A small project-local TypeScript harness layered on top of `node:test` is sufficient.

### Recommended support helpers

The toolkit test support layer should provide helpers such as:

- temporary-directory creation and cleanup
- fixture-tree copy helpers
- cached repository-root and project-root helpers
- optional one-time `lake build` helper
- one-shot subprocess execution helper with captured stdout/stderr/exit status
- managed subprocess helper for synthetic processes
- JSON-line helper for talking to `aftk_server`
- normalized-result assertion helpers
- minimal pi adapter spies/fakes for `registerTool`, `registerCommand`, and `on`

### Why toolkit tests need their own support layer

The existing Lean test harness under `AFTKTest/*` is appropriate for Lean suites.
But the TypeScript toolkit needs helpers around:

- Node subprocess APIs
- `AbortController`
- temp filesystem setup from TypeScript
- and host-adapter registration surfaces

So the toolkit should have its own lightweight test support modules rather than trying to tunnel everything through the Lean-side harness.

## Fixture strategy

Toolkit tests should use three kinds of fixtures.

### 1. Reused repository integration fixtures

These are the checked-in fixtures already owned by the lower layers.
Examples include:

- `tests/server/fixtures/lean/Informal.lean`
- `tests/server/fixtures/lean/Semantics.lean`
- `tests/server/fixtures/knowledgebase/basic-valid/`
- `tests/informal/knowledgebase-fixtures/basic-valid/`
- `tests/informal/knowledgebase-fixtures/long-body/`
- `AFTKTest.Informal.Fixtures.Basic`
- `AFTKTest.Informal.Fixtures.Imports.Base`
- `AFTKTest.Informal.Fixtures.Imports.Mid`
- `AFTKTest.Informal.Fixtures.Imports.Top`

These should be the primary basis for representative real integration tests.

### 2. Toolkit-owned synthetic process fixtures

These should model operational edge cases that are awkward to induce through real Lean executables.
Examples:

- child prints one valid JSON line and exits successfully
- child prints malformed non-empty stdout
- child emits large stderr output
- child sleeps past timeout
- child ignores `SIGTERM` and forces escalation

These fixtures are especially important for:

- runtime tests
- server-client protocol-failure tests
- stderr-bounding tests
- cleanup escalation tests

### 3. Temporary mutable copies

Any test that needs mutation should copy a fixture tree or file into a temporary directory first.
Examples:

- editing a Lean file to provoke reopen-required behavior
- future knowledge-base create/rename/delete/body-set tests
- validation tests that intentionally corrupt a copied manifest or node file

No mutable test should share its temp directory with another test.

## Recommended coverage by subsystem

### 1. Runtime helper tests

These should focus on toolkit-owned process and path behavior.

#### Pure/synthetic runtime tests

Cover cases such as:

- project-root discovery by upward search for `lakefile.toml` / `lakefile.lean`
- explicit failure on missing project root
- command-spec resolution and override validation
- one-shot command success with captured stdout/stderr
- one-shot timeout behavior
- one-shot cancellation behavior with `AbortController`
- bounded stderr ring-buffer behavior
- managed-process lazy start behavior
- idempotent stop behavior
- graceful-then-`SIGTERM`-then-`SIGKILL` escalation with synthetic stubborn children

#### Minimal real runtime tests

A small number of real-lower-layer smoke tests may confirm that the runtime helpers work with actual commands such as:

- `lake exe aftk_server`
- `lake exe aftk knowledgebase status`

The point is not to retest every lower-layer command here, only to ensure the runtime layer works against real commands as designed.

### 2. Output normalization tests

These should be mostly pure tests.

Cover cases such as:

- normalized success envelope shape
- normalized failure envelope shape
- error-kind/category mapping
- preservation of source-specific codes and exit codes
- warning handling
- truncation metadata
- text rendering for representative known errors
- bounded stderr inclusion policy
- validation-report success rendering even when the underlying command exit code is non-zero but semantically meaningful

Because `plans/toolkit/output.md` treats `details` as the stronger contract, these tests should emphasize `details` heavily.

### 3. Server-client tests

These should have both synthetic and real layers.

#### Synthetic server-client tests

Cover cases such as:

- JSON-RPC request id tracking
- generic `request<M>(...)` vs named method helpers
- malformed response envelopes
- JSON-RPC error envelope handling
- unknown response ids ignored or handled safely
- malformed non-empty stdout treated as protocol failure
- timeout vs cancellation distinction for pending requests
- `shutdown()` vs `stop(graceful?)` distinction

Synthetic line-based fake servers are the right tool here because they can deterministically send malformed or adversarial protocol output.

#### Real server-client integration tests

Cover representative behavior against:

```text
lake exe aftk_server
```

using real Lean fixtures.
Representative cases should include:

- `open` then a representative query such as `get_hover`
- `load_node` plus `get_goals`
- known error mapping for unopened files or stale node ids
- explicit semantic `shutdown`
- client cleanup after stop

Toolkit tests do **not** need to reproduce every hub/worker semantic case already covered in `plans/server/testing.md`.
They need enough real coverage to validate the TypeScript boundary.

### 4. Lean-tool-family tests

These should test the server-backed tool family above the client layer.

#### Fast tests with stub clients

Cover cases such as:

- the exact exported tool name set:
  - `aftk_open`
  - `aftk_close`
  - `aftk_load_node`
  - `aftk_get_hover`
  - `aftk_get_plain_goal`
  - `aftk_get_plain_term_goal`
  - `aftk_get_infoview`
  - `aftk_get_goals`
  - `aftk_run_tactic`
  - `aftk_run_tactic_steps`
  - `aftk_shutdown`
- parameter validation and required/optional parameter shape
- minimal path normalization behavior such as stripping one leading `@`
- preservation of raw server result payloads under `details.result`
- known server error rendering while preserving exact codes in details
- no hidden auto-open behavior

#### Representative real integration tests

Cover cases such as:

- `aftk_open` on a real fixture file
- `aftk_get_hover` on a representative site
- `aftk_load_node` followed by `aftk_get_goals`
- `aftk_run_tactic_steps` on a representative proof state
- `aftk_shutdown` producing semantic shutdown plus owned-process cleanup

The emphasis should remain on toolkit behavior:

- tool naming
- lifecycle expectations
- normalized details
- error mapping

not on re-proving all Lean semantics.

### 5. Knowledge-base bridge and tool-family tests

These should test the CLI-backed knowledge-base surface in two layers.

#### Fast tests

Cover cases such as:

- argv construction for each command wrapper
- `--root` forwarding when present
- omission of `--root` when absent
- parser behavior for success envelopes
- preservation of exact raw knowledge-base `command` strings such as `search.text`, `validate.storage`, and `relationships.related`
- parser behavior for failure envelopes
- validation exit-code-4 special case normalized as semantic success
- malformed JSON envelope treated as toolkit protocol failure
- exact initial exported tool name set:
  - `knowledgebase_status`
  - `knowledgebase_list`
  - `knowledgebase_show`
  - `knowledgebase_search_text`
  - `knowledgebase_search_tag`
  - `knowledgebase_relationships`
  - `knowledgebase_validate_storage`
  - `knowledgebase_validate_node`
  - `knowledgebase_validate_metadata`
  - `knowledgebase_validate_all`

#### Real integration tests

Cover representative calls against real fixture roots, such as:

- `status` on a valid root
- `list` and `show` on `basic-valid`
- `search text` and `search tag`
- representative relationship query
- `validate all` on a valid root
- `validate all` on an intentionally invalid copied root to confirm semantic-success report handling and exit-code preservation

These tests should strongly assert:

- normalized `details.backend`
- normalized `details.result`
- warning propagation
- preserved exit code
- actionable text summary

### 6. Informal bridge and tool-family tests

These should likewise have fast and real layers.

#### Fast tests

Cover cases such as:

- repeated `--module` argument formation from `modules: string[]`
- rejection of empty `modules` for environment-backed commands
- `informal_present` parameter mapping for `root`, `mode`, and `body`
- success-JSON parsing for each command family
- parsing of command-shaped `data`/`target`/`mode`/`bodyMode` variations
- failure-JSON parsing and normalization, including exact lower-layer codes such as `informal.notTracked`
- malformed JSON treated as toolkit protocol failure
- exact initial exported tool name set:
  - `informal_status`
  - `informal_decls`
  - `informal_decl`
  - `informal_refs`
  - `informal_ref`
  - `informal_deps`
  - `informal_present`

#### Real integration tests

Use real informal fixture modules and roots for representative cases such as:

- `informal_status` on `AFTKTest.Informal.Fixtures.Basic`
- `informal_decls` and `informal_decl`
- `informal_refs` and `informal_ref`
- `informal_deps` on `AFTKTest.Informal.Fixtures.Imports.Top`
- `informal_present` against `tests/informal/knowledgebase-fixtures/basic-valid`

These tests should assert:

- correct result normalization
- preservation of lower-layer semantic payloads in `details.result`
- deterministic ordering inherited from the lower layer for declarations/references/dependencies where relevant
- preview-body truncation metadata preservation for representative `informal_present` cases
- actionable text summaries
- stable error mapping for CLI failures

### 7. Host-adapter / pi-integration tests

These should focus on the thin adapter behavior rather than on full conversational pi runs.

#### Primary adapter tests

The majority of coverage should come from:

- direct execution of the generated custom tool definitions
- small in-memory spies/fakes for the subset of `ExtensionAPI` behavior the adapter uses

Representative cases:

- `registerToolkitExtension(...)` registers the expected tools
- the extension path registers `aftk-extension-stop`
- the stop command triggers toolkit cleanup but not global pi shutdown
- `session_shutdown` is hooked and performs cleanup
- family-selection options include/exclude the expected tools
- repeated cleanup is safe and idempotent

#### Optional SDK smoke tests

If practical without requiring a real model or network activity, add a very small number of smoke tests using documented SDK loader surfaces such as:

- `DefaultResourceLoader({ extensionFactories: [...] })`
- `DefaultResourceLoader({ additionalExtensionPaths: [...] })`

These tests should not rely on actual prompt execution.
Their purpose would only be to confirm that:

- the extension file loads
- registration occurs
- and the adapter is structurally compatible with the documented SDK loading path

## Mutation-test policy for future toolkit commands

The current initial knowledge-base tool family is intentionally query/report-oriented.
So v1 does not need a large mutation suite yet.

But the testing policy should already be explicit for later commands such as:

- `create`
- `rename`
- `delete`
- `body set`
- `metadata replace`

### Required policy for any future mutation tests

When mutation tools are added, their tests must:

- copy a checked-in fixture root into a fresh temp directory
- run the mutation only inside that temp copy
- assert both:
  - the returned normalized toolkit result,
  - and the resulting on-disk state
- avoid sharing the temp root across tests
- leave checked-in fixtures unchanged under all failure paths

### Why this policy matters now

`plans/toolkit/knowledgebase-tools.md` deliberately deferred mutation commands until the mutation-test story was explicit.
This document resolves that deferral by establishing the required temporary-copy policy.

## Determinism and flake-resistance policy

Toolkit tests will involve asynchronous subprocesses and timeouts.
That makes determinism an explicit design concern.

A good v1 policy is:

- use generous but bounded timeouts in integration tests
- prefer explicit readiness checks over arbitrary sleeps where possible
- isolate each real managed process per test or per suite
- isolate each mutable temp filesystem tree per test
- keep integration tests conservative in parallelism
- use synthetic fixtures for adversarial timing cases instead of trying to coax the real Lean stack into pathological behavior on demand

## Boundaries and anti-patterns

The toolkit test suite should explicitly avoid the following mistakes.

### 1. No treating `tsc --noEmit` as the toolkit test strategy

Typechecking is necessary but not sufficient.
The toolkit’s operational behavior must be tested.

### 2. No forcing TypeScript tests into the Lake driver

`lake test` should continue to mean the Lean-layer suite.
Toolkit tests should have their own native workflow.

### 3. No Bun-specific test-runner dependency as the core strategy

The runtime and tests should share the same Node-compatible assumptions.

### 4. No mutation of checked-in fixture files or roots

Mutable scenarios must use temp copies.

### 5. No exhaustive reimplementation of lower-layer semantic test suites in TypeScript

Representative end-to-end checks are good.
Whole-layer semantic duplication is not.

### 6. No mocks-only strategy for subprocess boundaries

Real lower-layer integration tests are required.
Synthetic fixtures complement them; they do not replace them.

### 7. No dependence on networked model calls or interactive UI for ordinary toolkit tests

The toolkit layer can and should be tested below that level.

### 8. No fragile golden dependence on version-sensitive Lean pretty-printing

Use focused text assertions unless exact formatting is truly a toolkit-owned contract.

## Initial implementation checklist for this testing design

Before the toolkit layer can be considered well-tested, AFTK should reach at least this baseline:

- `tests/toolkit/` exists with subsystem-specific test directories
- toolkit test support helpers exist for temp fixtures, subprocess execution, and normalized-result assertions
- toolkit-owned synthetic process fixtures exist for timeout, malformed output, stderr flood, and shutdown-escalation cases
- package scripts exist for:
  - typecheck
  - toolkit unit tests
  - toolkit integration tests
  - full combined test workflow
- representative real subprocess tests exist for:
  - `aftk_server`
  - `aftk knowledgebase`
  - `aftk informal`
- normalized output envelopes are tested structurally
- exact initial tool name sets are tested for Lean, knowledge-base, and informal families
- host-adapter tests cover extension registration, stop command behavior, and cleanup hooks
- mutation-capable tests, when added later, use temp-copy fixture policy rather than in-place fixture mutation

## Summary

AFTK should treat toolkit testing as a first-class TypeScript concern rather than an afterthought.
That means:

- keeping Lean-layer tests under `lake test`,
- adding a dedicated package-level toolkit test workflow,
- using a Node-native test runner,
- splitting fast synthetic tests from real subprocess integration tests,
- reusing the repository’s existing fixtures wherever they already encode the lower-layer truth,
- adding toolkit-owned synthetic process fixtures for operational edge cases,
- and focusing assertions on the toolkit’s real contracts:
  - process behavior,
  - output normalization,
  - exact tool surfaces,
  - and thin pi adapter behavior.

This gives the rewrite a testing story that matches its architecture:

- lower layers keep owning their deep semantics,
- the toolkit owns the TypeScript/process/normalization boundary above them,
- and the repository gets a clear full-stack validation workflow without collapsing everything into one test runner.
