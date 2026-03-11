# Plan: unified server surface for knowledgebase + informal

## Goal

Extend `aftk_server` so it is the single public programmatic interface for:

- file-worker-backed Lean queries and tactic exploration
- direct knowledgebase operations
- direct informal-layer queries and presentation

while keeping the existing CLIs:

- `lake exe aftk knowledgebase ...`
- `lake exe aftk informal ...`

The important refactor is to share **execution logic**, not CLI presentation logic, so the CLI and server both sit on top of the same reusable layer-specific services.

## Non-goals

This change should **not**:

- shell out from the server to `lake exe aftk knowledgebase ...` or `lake exe aftk informal ...`
- move knowledgebase/informal work into file workers
- change existing file-worker server methods (`open`, `get_hover`, `run_tactic`, etc.)
- make the server return CLI text or CLI-shaped JSON envelopes
- remove the existing CLIs

## Research summary

### 1. What the server does today

Relevant files:

- `AFTK/Server/Protocol.lean`
- `AFTK/Server/Transport.lean`
- `AFTK/Server/Hub.lean`
- `AFTK/Server/Main.lean`
- `AFTK/FileWorker/**`
- `docs/server/overview.md`
- `docs/server/protocol.md`

Current public server methods are only the file/session methods:

- `open`
- `close`
- `load_node`
- `get_hover`
- `get_plain_goal`
- `get_plain_term_goal`
- `get_infoview`
- `get_goals`
- `run_tactic`
- `run_tactic_steps`
- `shutdown`

`AFTK.Server.Hub` is intentionally thin:

- it normalizes/canonicalizes paths
- manages one worker session per open Lean file
- checks file freshness and worker liveness
- forwards requests to file workers
- implements `run_tactic_steps` at the hub level

The docs explicitly call out a current limitation in `docs/server/overview.md`:

- **no first-class server methods for generic knowledge-base operations**

So the feature request matches an existing documented gap.

### 2. The server already reuses the informal + knowledgebase libraries internally

Relevant file:

- `AFTK/FileWorker/Informal.lean`

The server is already not purely "Lean hover/tactic only" internally:

- richer hover at `informal[...]` sites resolves references through `AFTK.Informal`
- that in turn resolves through `AFTK.KnowledgeBase`

So there is already precedent for the server layer directly depending on the lower layers.
The missing piece is a **public handler surface**, not basic library access.

### 3. How knowledgebase interaction is implemented today

Relevant files:

- `AFTK/KnowledgeBase/Types.lean`
- `AFTK/KnowledgeBase/PathLayout.lean`
- `AFTK/KnowledgeBase/Storage.lean`
- `AFTK/KnowledgeBase/Search.lean`
- `AFTK/KnowledgeBase/Validation.lean`
- `AFTK/KnowledgeBase/Cli/Types.lean`
- `AFTK/KnowledgeBase/Cli/Parse.lean`
- `AFTK/KnowledgeBase/Cli/Render.lean`
- `AFTK/KnowledgeBase/Cli/Main.lean`

Important current structure:

- the real filesystem/domain logic already lives below the CLI in `Storage`, `Search`, and `Validation`
- `Cli/Main.lean` contains a private `dispatch` function that maps CLI commands onto those library functions
- `Cli/Main.lean` also owns CLI-specific concerns like:
  - `InputSource` reading (`stdin` / file)
  - root resolution for command execution
  - exit-code handling
  - stdout/stderr printing

This is a good starting point, but the reusable execution boundary is still too CLI-local:

- `dispatch` is private to `Cli/Main.lean`
- body/metadata replacement still flow through CLI-oriented input abstractions

A useful detail: most knowledgebase read-side result types already have `ToJson` instances, for example:

- `NodeId`
- `NodeMetadata`
- `Node`
- `StoredNode`
- `NodePaths`
- `KnowledgeBaseStoragePaths`
- `Search.SearchResult`
- `Validation.ValidationReport`

But write-side structured decoding is incomplete:

- `Relationship`, `LeanDeclRef`, and `NodeMetadata` do **not** currently have `FromJson` instances

That matters if the server is to accept structured metadata replacement requests instead of CLI-style text blobs.

### 4. How informal interaction is implemented today

Relevant files:

- `AFTK/Informal/References.lean`
- `AFTK/Informal/Tracking.lean`
- `AFTK/Informal/Dependencies.lean`
- `AFTK/Informal/Presentation.lean`
- `AFTK/Informal/Cli/Types.lean`
- `AFTK/Informal/Cli/Parse.lean`
- `AFTK/Informal/Cli/Render.lean`
- `AFTK/Informal/Cli/Main.lean`
- `docs/informal/library.md`

Current structure:

- the semantic/query logic already exists in reusable library modules:
  - tracking queries in `Tracking.lean`
  - dependency views in `Dependencies.lean`
  - presentation logic in `Presentation.lean`
  - direct knowledgebase-backed resolution in `References.lean`
- but `Cli/Main.lean` still owns the operational execution layer:
  - `importEnvironment`
  - `runCoreInEnv`
  - `commandResultInEnv`
  - `presentResult`
  - `commandResult`

So unlike the knowledgebase CLI, the informal CLI still has more of its reusable execution path trapped inside `Cli/Main.lean`.

Important behavioral split already exists today:

- environment-backed commands:
  - `status`
  - `decls`
  - `decl`
  - `refs`
  - `ref`
  - `deps`
- direct knowledgebase-backed command:
  - `present`

That split should be preserved in the refactor.

A second important detail: informal CLI success JSON is currently command-shaped and manually rendered in `AFTK/Informal/Cli/Render.lean`, unlike the knowledgebase CLI which uses a common `ok/result` envelope.
That difference is fine for CLI UX, but it is exactly why the server should **not** try to reuse CLI renderers.

Also relevant: several informal core result types do not currently have `ToJson` instances:

- `InformalDeclEntry`
- `InformalReferenceEntry`
- `InformalDeclDependencyEntry`
- `InformalReferenceDependencyEntry`

The CLI works around this by manually assembling JSON in the renderer.
The server will need either:

- server-specific DTO/result types, or
- new `ToJson` instances / serialization helpers for these results

### 5. Existing error model mismatch

Relevant files:

- `AFTK/Server/Protocol.lean`
- `AFTK/KnowledgeBase/Types.lean`

Today there are two different public error styles:

1. server/file-worker JSON-RPC errors
   - numeric JSON-RPC codes
   - e.g. `fileNotOpen`, `fileChanged`, `workerUnavailable`, `staleNode`

2. knowledgebase/informal CLI errors
   - `KnowledgeBaseError` with:
     - `code : String`
     - `message : String`
     - `exitCode : UInt8`

For a unified server surface, the execution layer should keep using `KnowledgeBaseError`, but the server must map it into **JSON-RPC errors**, not CLI output.

### 6. Long-running server changes the concurrency story

Today the CLIs are one-command processes, so mutation races are mostly irrelevant.
Once knowledgebase operations are handled inside `aftk_server`, concurrent requests become possible.
That means the server refactor should explicitly consider synchronization for:

- `init`
- `create`
- `rename`
- `delete`
- `set body`
- `replace metadata`

At minimum, v1 should not allow concurrent mutations to interleave unsafely.

### 7. Current Python client status and implications

Relevant files:

- `aftk_client/client.py`
- `aftk_client/models.py`
- `aftk_client/errors.py`
- `aftk_client/jsonrpc.py`
- `aftk_client/transport.py`
- `aftk_client/__init__.py`
- `tests/python/test_models.py`
- `tests/python/test_project_root.py`
- `tests/python/test_client_integration.py`
- `plans/aftk-client.md`

Current Python client structure already mirrors the current file-worker server surface closely:

- `AsyncAftkClient` in `aftk_client/client.py` provides one wrapper per existing public server method
- `aftk_client/models.py` contains Pydantic request/result models only for the current file/session methods
- `aftk_client/errors.py` only maps the current JSON-RPC error codes:
  - `-32602`
  - `-32603`
  - `-32001`
  - `-32010`
  - `-32011`
  - `-32012`
  - `-32013`
- `aftk_client/__init__.py` only re-exports those current models and exceptions
- the Python integration tests currently only cover the existing file-worker flow:
  - open/query/tactic lifecycle
  - project-root detection
  - concurrent requests
  - client-side param validation

An important positive finding is that the transport/runtime is already generic enough for the new server methods:

- `AsyncJsonRpcSubprocessTransport` is method-agnostic and only assumes newline-delimited JSON-RPC
- `AsyncAftkClient.request(...)` already accepts an arbitrary `RequestModel` plus arbitrary result type validated by Pydantic `TypeAdapter`
- project-root / Lake-root handling is already solved in the Python client and should continue to work for the expanded server surface

So the Python-side follow-on work is mostly about:

- adding new Pydantic request/result models
- adding new high-level client wrapper methods
- extending JSON-RPC error-code mapping
- extending exports and tests

That means the unified-server feature should explicitly plan a Python-client update phase after the server methods land, but it does **not** appear to require a transport redesign.

## Recommended design

### 1. Introduce reusable execution modules below CLI/server

Add new shared execution modules:

- `AFTK/KnowledgeBase/Service.lean`
- `AFTK/Informal/Service.lean`

These should own reusable command execution logic.
The layering should become:

- library/domain code
- service execution layer
- CLI adapter (`argv` parsing + input loading + rendering)
- server adapter (JSON param decoding + JSON-RPC error mapping)

The key point is:

- **CLI keeps parsing/rendering responsibilities**
- **server keeps transport/protocol responsibilities**
- **shared service modules own the actual operation semantics**

### 2. Do not mirror the CLI command tree in the server protocol

Avoid a generic RPC like:

- `knowledgebase_execute { command = ... }`
- `informal_execute { command = ... }`

That would couple the server to CLI-only concepts such as:

- `InputSource`
- `OutputFormat`
- help topics
- CLI command nesting choices
- exit-code-oriented failure handling

Instead, add method-specific RPC handlers, which matches the existing server style and is easier for clients to model.

### 3. Keep server methods additive and explicitly namespaced

Use additive public method names with clear prefixes, for example:

#### Knowledgebase methods

- `knowledgebase_init`
- `knowledgebase_status`
- `knowledgebase_list`
- `knowledgebase_show`
- `knowledgebase_get_body`
- `knowledgebase_get_metadata`
- `knowledgebase_get_paths`
- `knowledgebase_create`
- `knowledgebase_rename`
- `knowledgebase_delete`
- `knowledgebase_set_body`
- `knowledgebase_replace_metadata`
- `knowledgebase_validate_metadata`
- `knowledgebase_validate_storage`
- `knowledgebase_validate_node`
- `knowledgebase_validate_all`
- `knowledgebase_search_text`
- `knowledgebase_search_tag`
- `knowledgebase_relationships_outgoing`
- `knowledgebase_relationships_incoming`
- `knowledgebase_relationships_related`

#### Informal methods

- `informal_status`
- `informal_decls`
- `informal_decl`
- `informal_refs`
- `informal_ref`
- `informal_decl_deps`
- `informal_ref_deps`
- `informal_present`

This keeps the current server contract backward-compatible while making the new layer surfaces explicit.

### 4. Make the server protocol structured, not CLI-shaped

Server params should be object-shaped and method-specific, as they already are today.

Important protocol design rules:

- no `OutputFormat` in server params
- no help methods / help rendering in the server
- no `stdin`/`file`-style input sources in server params
- direct values instead of CLI input abstractions

Examples:

- `knowledgebase_create` should accept an optional `body : String`, not `bodySource`
- `knowledgebase_set_body` should accept `body : String`
- `knowledgebase_replace_metadata` should accept structured metadata JSON, not raw JSON text
- `informal_present` should accept `mode` and `bodyMode` as structured params, not CLI flags

### 5. Preserve current root-resolution semantics

For both knowledgebase and informal server methods:

- if `root?` is omitted, keep using `PathLayout.resolveRootPath`
- this preserves the same default-root policy as the existing CLI/library behavior
- the effective server cwd therefore still matters, which is already true today

### 6. Preserve the informal environment-backed vs direct-backed split

In `AFTK/Informal/Service.lean` keep the same conceptual split that exists today:

#### Environment-backed operations

Require `modules : Array Name` (or string params parsed into names):

- status
- decls
- decl
- refs
- ref
- decl deps
- ref deps

#### Direct knowledgebase-backed operation

Does **not** require imported modules:

- present

This keeps the model consistent with the current CLI.

## Proposed shared-service refactor

### A. Knowledgebase service module

Create a reusable module that exposes execution functions close to the current private `dispatch` cases, for example:

- `statusInfoForRoot`
- `listNodes`
- `showNode`
- `showBody`
- `showMetadata`
- `showPaths`
- `createNode`
- `renameNode`
- `deleteNode`
- `setNodeBody`
- `replaceNodeMetadata`
- `validateMetadata`
- `validateStorage`
- `validateNode`
- `validateAll`
- `searchText`
- `searchTag`
- `outgoingRelationships`
- `incomingRelationships`
- `relatedRelationships`

The write-side functions should take direct values, not CLI abstractions.
For example:

- `createNode ... (body : String)`
- `setNodeBody ... (body : String)`
- `replaceNodeMetadata ... (metadata : NodeMetadata)`

Then `AFTK/KnowledgeBase/Cli/Main.lean` becomes a thin adapter:

1. parse argv
2. resolve/load CLI-only inputs (`stdin`, files)
3. call the shared service function
4. render the result

### B. Informal service module

Create a reusable module that extracts the operational logic from `AFTK/Informal/Cli/Main.lean`, especially:

- environment import
- `CoreM` execution in an imported environment
- not-tracked error mapping
- direct `present` resolution

Possible helpers:

- `importEnvironment`
- `runCoreInEnv`
- `status`
- `decls`
- `decl`
- `refs`
- `ref`
- `declDeps`
- `refDeps`
- `present`

Then `AFTK/Informal/Cli/Main.lean` becomes a thin adapter:

1. parse argv
2. call service functions
3. render the result

### C. Keep CLI renderers unchanged as much as possible

`Cli/Render.lean` files are presentation code.
They should stay CLI-specific.

What should be reused:

- execution semantics

What should not be reused:

- text rendering
- command-shaped success JSON
- CLI failure rendering
- help text

## Proposed server protocol/result design

### 1. Add server param/result structs for the new methods

Keep the current `AFTK.Server.Protocol` style:

- one struct per request family
- one struct per result family when needed
- derive `FromJson` for params
- derive `ToJson` for results

Because this will add many types, it may be worth splitting the protocol file into submodules, e.g.:

- `AFTK/Server/Protocol/File.lean`
- `AFTK/Server/Protocol/KnowledgeBase.lean`
- `AFTK/Server/Protocol/Informal.lean`
- `AFTK/Server/Protocol.lean` re-exporting them

That split is not mandatory, but it is likely cleaner once the server surface grows beyond file-worker methods.

### 2. Prefer typed domain values where practical

Use direct domain types in params/results when instances already exist and the JSON shape is stable, for example:

- `NodeId`
- `NodeKind`
- `NodeStatus`
- `InformalReference`

But avoid exposing raw Lean `Name` JSON unless the shape is intentionally stable.
For informal server results, prefer explicit strings such as:

- `declName : String`
- `declNames : Array String`

That is closer to the current CLI JSON behavior and friendlier for non-Lean clients.

### 3. Suggested result DTOs for informal methods

Because the core informal tracking/dependency rows do not currently have transport-friendly JSON instances, introduce explicit server result DTOs such as:

- `InformalDeclDto`
  - `declName : String`
  - `refs : Array String`
  - `refCount : Nat`
- `InformalRefDto`
  - `ref : String`
  - `declNames : Array String`
  - `declCount : Nat`
- `InformalDeclDependencyDto`
  - `declName : String`
  - `dependencies : Array String`
- `InformalRefDependencyDto`
  - `ref : String`
  - `dependencies : Array String`

Then server results can be stable without forcing the core tracking types to become transport-layer types.

### 4. `informal_present` can stay as one method

Unlike the other informal commands, `present` already maps naturally onto a structured payload.
One reasonable result shape is:

- `mode : "compact" | "rich"`
- `summary : InformalPresentationSummary`
- `payload? : Option InformalPresentationPayload`
- `bodyMode? : Option String`

So:

- compact mode returns `summary` only
- rich mode returns `summary` plus `payload`

### 5. Keep the server protocol Python-client-friendly

Because `aftk_client/` is already a real consumer of the server, the new server methods should be shaped so the Python update is straightforward.

Concretely:

- prefer explicit method-specific request/response structs over generic command blobs
- prefer stable object-shaped JSON that maps cleanly to Pydantic models
- prefer plain strings for Lean names in transport-facing DTOs
- avoid requiring the Python client to understand CLI-only concepts like help topics, output formats, or `InputSource`
- keep result shapes deterministic across commands instead of mixing domain JSON with CLI-rendered envelopes

For Python error handling, if the server adds new domain-level JSON-RPC error codes, the error `data` should remain stable and machine-readable.
A good target shape is:

- `layer : "knowledgebase" | "informal"`
- `code : String`
- `message : String`
- `exitCode : Nat`

That lets the Python client preserve both:

- JSON-RPC-level classification via numeric error code, and
- lower-layer identity via structured error payload

## Error-mapping plan

### 1. Param validation stays JSON-RPC `invalid params`

Use ordinary JSON-RPC invalid-params errors for:

- malformed method params
- invalid enum strings in params
- invalid dotted declaration/module names
- invalid node ids/references supplied as strings
- missing required modules where applicable

This is the server equivalent of CLI usage errors.

### 2. Execution errors should map from `KnowledgeBaseError`

For shared knowledgebase/informal execution errors:

- do **not** return CLI failure JSON as a successful result
- do **not** use stdout/stderr text rendering
- map `KnowledgeBaseError` into JSON-RPC errors in `AFTK.Server.Protocol`

Recommended mapping:

- `KnowledgeBaseError.usage` -> JSON-RPC `invalid params`
- `KnowledgeBaseError.notFound` -> new server error code, e.g. `domainNotFound`
- `KnowledgeBaseError.validation` -> new server error code, e.g. `domainValidation`
- `KnowledgeBaseError.conflict` -> new server error code, e.g. `domainConflict`
- generic -> new server error code, e.g. `domainError`

And include structured error `data`, for example:

- `layer : "knowledgebase" | "informal"`
- `code : String`
- `message : String`
- `exitCode : Nat`

That preserves the lower-layer error identity while still behaving like a real server protocol.

## Concurrency/state plan

### 1. Keep file-worker state separate from domain-operation state

`AFTK.Server.Hub.Context` currently only carries the file-session state mutex.
To support server-side knowledgebase operations safely, extend the context with at least:

- a knowledgebase-operation mutex

A conservative v1 choice is a single global mutex for all knowledgebase operations.
That is simpler than root-scoped locking and is good enough for correctness.

### 2. Reads vs writes

The safest first version is:

- serialize all knowledgebase operations through one mutex

This avoids races like:

- `list` interleaving with `rename`
- `show` interleaving with `delete`
- `validate all` interleaving with `replace metadata`

It is conservative, but correctness matters more than throughput here.
If needed later, this can be refined to root-scoped or read/write locking.

### 3. Informal environment caching should be optional, not required for v1

Because the informal CLI currently imports modules per invocation, the simplest server refactor is to preserve that behavior and keep informal queries stateless.

If performance becomes an issue, add a cache later behind the service boundary, keyed by at least:

- imported module array
- maybe process/project context if needed

But this should not block the initial unification refactor.

## Concrete file plan

### New modules

- `AFTK/KnowledgeBase/Service.lean`
- `AFTK/Informal/Service.lean`
- `AFTK/Server/KnowledgeBaseHandlers.lean`
- `AFTK/Server/InformalHandlers.lean`

### Existing modules likely to change

- `AFTK/KnowledgeBase/Cli/Main.lean`
- `AFTK/Informal/Cli/Main.lean`
- `AFTK/Server/Protocol.lean` (or split protocol submodules)
- `AFTK/Server/Hub.lean`
- `AFTK/Server/Main.lean`
- `AFTK/KnowledgeBase/Types.lean` (for missing `FromJson` instances if structured metadata input is added)

### Possibly updated public roots

Depending on how public we want the shared services to be:

- `AFTK/KnowledgeBase.lean`
- `AFTK/Informal.lean`
- `AFTK/Server.lean`

### Python files likely to change

- `aftk_client/models.py`
- `aftk_client/client.py`
- `aftk_client/errors.py`
- `aftk_client/__init__.py`
- `tests/python/test_models.py`
- `tests/python/test_client_integration.py`
- possibly new Python integration/error tests if the suite becomes large enough to split

## Python client update plan

Once the new server methods exist, update `aftk_client/` so the Python client remains a first-class typed consumer of the unified server surface.

### 1. Keep the transport layer unchanged unless the server protocol itself changes

Based on the current code in `aftk_client/transport.py` and `aftk_client/jsonrpc.py`, the transport layer should not need meaningful changes if the server continues to use:

- newline-delimited JSON-RPC over stdio
- object-shaped params
- ordinary JSON-RPC success/error envelopes

So the Python work should be concentrated in models, wrappers, exports, and tests.

### 2. Extend `aftk_client/models.py` with new request/result models

Add Pydantic request/result models for the new server methods.

This likely includes knowledgebase-side models for:

- storage/root status
- node metadata, node paths, and stored nodes
- search results
- validation reports
- relationship results
- create/rename/delete/set-body/replace-metadata requests

and informal-side models for:

- status results
- declaration/reference entry DTOs
- dependency DTOs
- presentation request/result models

Because `aftk_client/models.py` currently only contains file-worker models, it may be worth either:

- keeping one larger `models.py` file for now, or
- splitting into submodules such as:
  - `aftk_client/models_file.py`
  - `aftk_client/models_knowledgebase.py`
  - `aftk_client/models_informal.py`

Either approach is fine; the main requirement is that the new server methods have typed request/result models.

### 3. Extend `AsyncAftkClient` with wrapper methods for the new RPC surface

Add one high-level wrapper per new server method, following the style already used for:

- `open`
- `close`
- `load_node`
- `get_hover`
- `run_tactic`

Recommended wrappers are the server-method-shaped ones, for example:

- `knowledgebase_init(...)`
- `knowledgebase_status(...)`
- `knowledgebase_list(...)`
- `knowledgebase_show(...)`
- `knowledgebase_get_body(...)`
- `knowledgebase_get_metadata(...)`
- `knowledgebase_get_paths(...)`
- `knowledgebase_create(...)`
- `knowledgebase_rename(...)`
- `knowledgebase_delete(...)`
- `knowledgebase_set_body(...)`
- `knowledgebase_replace_metadata(...)`
- `knowledgebase_validate_metadata(...)`
- `knowledgebase_validate_storage(...)`
- `knowledgebase_validate_node(...)`
- `knowledgebase_validate_all(...)`
- `knowledgebase_search_text(...)`
- `knowledgebase_search_tag(...)`
- `knowledgebase_relationships_outgoing(...)`
- `knowledgebase_relationships_incoming(...)`
- `knowledgebase_relationships_related(...)`
- `informal_status(...)`
- `informal_decls(...)`
- `informal_decl(...)`
- `informal_refs(...)`
- `informal_ref(...)`
- `informal_decl_deps(...)`
- `informal_ref_deps(...)`
- `informal_present(...)`

Because `AsyncAftkClient.request(...)` is already generic, these wrappers should mostly be thin typed adapters.

### 4. Extend Python error mapping for the new server error codes

If the server adds domain-level JSON-RPC errors for knowledgebase/informal failures, update `aftk_client/errors.py` to include matching exception classes and numeric-code mapping.

A likely shape is:

- `DomainRequestError`
  - `DomainNotFoundError`
  - `DomainValidationError`
  - `DomainConflictError`
  - `DomainOperationError`

or equivalent naming.

The exception instances should continue to preserve:

- `code`
- `message`
- `data`
- `method`
- `request_id`

If the server uses structured error `data`, the Python client may also add a small Pydantic/dataclass helper to decode that payload for easier downstream inspection.

### 5. Update public exports

Update `aftk_client/__init__.py` so the new models and exceptions are public the same way the current file-worker models are.

### 6. Add Python tests for the expanded server surface

Extend the existing Python test suite under `tests/python/`.

At minimum add:

- model-validation tests for the new request/result models
- error-mapping tests for the new domain-level JSON-RPC error codes
- integration tests against real `aftk_server` subprocesses for representative:
  - knowledgebase read methods
  - knowledgebase write methods
  - informal environment-backed methods
  - informal `present`
- regression tests confirming the existing file-worker client methods still behave as before

The existing tests already establish the pattern:

- `tests/python/test_models.py`
- `tests/python/test_project_root.py`
- `tests/python/test_client_integration.py`

so the new coverage should extend that layout rather than invent a separate harness.

### 7. Keep project-root behavior consistent

The current Python client already treats the Lake project root as a first-class startup concern.
That should remain unchanged.

For the new server methods:

- if a method takes `root?`, the client should accept an explicit optional root path and send it verbatim
- if `root?` is omitted, the server should keep using its default root-resolution policy relative to the process cwd/project root

So the current project-root design in `AsyncAftkClient` remains valid for the expanded surface.

## Testing plan

### 1. Keep existing tests green

These should continue to pass with unchanged external behavior:

- `AFTKTest/KnowledgeBase/Cli.lean`
- `AFTKTest/Informal/Cli.lean`
- existing server worker/hub/process tests

### 2. Add direct service-level tests where the refactor creates new reusable logic

Especially for:

- knowledgebase service write paths that now take direct values instead of `InputSource`
- informal service environment-backed queries vs `present`
- any new error-mapping helpers

### 3. Add server process tests for knowledgebase handlers

Using the existing JSON-RPC subprocess harness pattern from `AFTKTest/Server/Fixtures.lean` and `AFTKTest/Server/Process.lean`, cover at least:

- `knowledgebase_init`
- `knowledgebase_create`
- `knowledgebase_show`
- `knowledgebase_get_body`
- `knowledgebase_get_metadata`
- `knowledgebase_set_body`
- `knowledgebase_replace_metadata`
- validation calls
- search calls
- relationship calls

Error-path coverage should include at least:

- invalid node id -> invalid params
- missing node -> domain not-found error
- metadata id mismatch -> domain conflict/validation as appropriate
- create existing node -> domain conflict error

### 4. Add server process tests for informal handlers

Cover at least:

- `informal_status`
- `informal_decls`
- `informal_decl`
- `informal_refs`
- `informal_ref`
- `informal_decl_deps`
- `informal_ref_deps`
- `informal_present`

Error-path coverage should include at least:

- missing required `modules` for environment-backed calls -> invalid params
- invalid declaration/module name string -> invalid params
- invalid informal reference -> invalid params
- missing tracked declaration/reference -> domain not-found error
- malformed knowledgebase node during `present` -> domain validation error

### 5. Add at least one serialization test for structured metadata input

If `knowledgebase_replace_metadata` accepts structured JSON, add tests that decode server params into:

- `Relationship`
- `LeanDeclRef`
- `NodeMetadata`

so the wire format is protected explicitly.

### 6. Add Python client tests for the new methods

Once the server-side methods exist, extend `tests/python/` to cover the new surface.

Suggested coverage:

- request/result model validation for new knowledgebase and informal models
- JSON-RPC error-code mapping for new domain-level error codes
- subprocess integration tests for representative knowledgebase read/write flows
- subprocess integration tests for representative informal query/presentation flows
- regression tests showing current file-worker methods still work unchanged through `AsyncAftkClient`

Because the Python client already has real subprocess integration tests, this should be a direct extension of the current harness rather than a separate mock-only test layer.

## Documentation updates

Update at least:

- `docs/server/overview.md`
- `docs/server/protocol.md`
- `docs/server/library.md`
- `docs/architecture.md`

Key doc changes:

- the server is no longer only the file-worker hub surface
- knowledgebase + informal handlers are first-class public server methods
- these methods are direct JSON-RPC methods, not CLI-through-server shims
- they do not require `open`
- they use JSON-RPC errors, not CLI output envelopes

Possible follow-on docs:

- `docs/knowledgebase/overview.md`
- `docs/informal/overview.md`

to mention the server as an additional interaction path beyond CLI/library use.

Python-facing docs should also be updated once the client wrappers exist, at least in:

- `README.md`
- and, if we keep separate planning/usage notes, `plans/aftk-client.md`

so the documented Python client surface stays aligned with the expanded server protocol.

## Implementation phases

### Phase 1: extract reusable knowledgebase execution

- add `AFTK/KnowledgeBase/Service.lean`
- move the reusable execution logic out of `Cli/Main.lean`
- keep CLI behavior identical
- add any missing structured decoding support needed for server write methods

### Phase 2: extract reusable informal execution

- add `AFTK/Informal/Service.lean`
- move environment import + command execution logic out of `Cli/Main.lean`
- keep CLI behavior identical

### Phase 3: extend server protocol + handlers

- add knowledgebase/informal request/result types
- add JSON-RPC error mapping helpers for `KnowledgeBaseError`
- add stateless knowledgebase/informal handlers
- register them in the hub server
- extend server context with a knowledgebase-operation mutex

### Phase 4: tests

- add direct service tests where useful
- add server subprocess tests for the new RPC methods
- keep existing CLI/server suites passing

### Phase 5: docs

- update server architecture/protocol docs
- note that server interaction now spans all three implemented layers

### Phase 6: Python client update

- extend `aftk_client/models.py` with knowledgebase/informal request/result models
- add `AsyncAftkClient` wrapper methods for the new RPCs
- extend `aftk_client/errors.py` for new domain-level JSON-RPC error codes
- update `aftk_client/__init__.py` exports
- add Python model/integration/error-mapping tests under `tests/python/`

## Recommended acceptance criteria

This feature/refactor is complete when all of the following are true:

- `aftk_server` exposes first-class knowledgebase and informal JSON-RPC handlers
- existing file-worker server methods remain unchanged
- the CLI behavior and UX for `aftk knowledgebase ...` and `aftk informal ...` remain unchanged
- the CLI no longer owns the only copy of knowledgebase/informal execution logic
- server handlers do not shell out to the CLIs
- server errors for knowledgebase/informal operations are real JSON-RPC errors with preserved lower-layer error identity
- server tests cover representative success and failure paths for both new handler families
- `aftk_client/` exposes typed wrappers/models for the new server methods
- Python tests cover representative success and failure paths for the expanded server surface

## Deferred follow-ons

Reasonable follow-ons after this lands, but not prerequisites:

- add higher-level Python convenience facades on top of the one-to-one RPC wrappers if the API becomes too broad
- add informal environment caching if repeated imports become a bottleneck
- refine the knowledgebase mutex into root-scoped or read/write locking if concurrency warrants it
