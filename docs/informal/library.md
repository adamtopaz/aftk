# Informal implementation guide

This document is the component-level implementation map for the informal layer.
It explains how `informal[...]` is implemented today, which files own which responsibilities, and how the CLI is wired to the library.

## Public entrypoints and code roots

Main code pointers:

- umbrella re-export: `AFTK.lean`
- informal public root: `AFTK/Informal.lean`
- top-level CLI dispatch: `Main.lean`
- informal CLI implementation: `AFTK/Informal/Cli/*`

The public library import is:

```lean
import AFTK.Informal
```

The public CLI entrypoint is:

```text
lake exe aftk_cli informal ...
```

## Component map

| Component | Main code | Responsibility |
| --- | --- | --- |
| Public root | `AFTK/Informal.lean` | Re-exports the reusable informal modules |
| Syntax | `AFTK/Informal/Syntax.lean` | `informal[...]` syntax category and helper extraction |
| Placeholder | `AFTK/Informal/Placeholder.lean` | Unsound placeholder primitive used during elaboration |
| Options | `AFTK/Informal/Options.lean` | `aftk.informal.root` Lean option |
| References | `AFTK/Informal/References.lean` | Node-id validation and knowledge-base-backed reference resolution |
| Tracking | `AFTK/Informal/Tracking.lean` | Persistent declaration→reference tracking |
| Dependencies | `AFTK/Informal/Dependencies.lean` | Derived declaration and reference dependency views |
| Presentation | `AFTK/Informal/Presentation.lean` | Compact and rich rendering of resolved references |
| Elaborator | `AFTK/Informal/Elaborator.lean` | Actual term elaborator for `informal[...]` |
| CLI command model | `AFTK/Informal/Cli/Types.lean` | Parsed command AST and result types |
| CLI parser | `AFTK/Informal/Cli/Parse.lean` | Argument parsing and help handling |
| CLI renderer | `AFTK/Informal/Cli/Render.lean` | Text/JSON rendering and help text |
| CLI dispatcher | `AFTK/Informal/Cli/Main.lean` | Environment import, command dispatch, result selection |

## Root and re-export surfaces

### `AFTK.lean`

Project-wide umbrella import.
It exposes the informal layer alongside the other implemented layers.

### `AFTK/Informal.lean`

Thin public root that re-exports:

- `Syntax`
- `Placeholder`
- `References`
- `Tracking`
- `Dependencies`
- `Presentation`
- `Options`
- `Elaborator`

It does not re-export the CLI modules.
That keeps library reuse separate from command-line code.

## Core component details

### `AFTK/Informal/Syntax.lean`

This file defines the surface syntax recognized by the elaborator.

Main responsibility:

- introduce bracketed syntax of the form `informal[group.basic.definition]`

Important detail:

- the syntax only parses an identifier-shaped payload
- semantic validation still happens later through the knowledge-base `NodeId` rules

Useful helper:

- `informalNodeIdString?`

This is intentionally a small parsing layer, not the semantic layer.

### `AFTK/Informal/Placeholder.lean`

This file defines the primitive that lets gradual formalization typecheck.

Core definition:

```lean
axiom Informal.{u} (tag : Lean.Name) (α : Sort u) : α
```

Implementation role:

- gives the elaborator a way to produce a value of the required type
- keeps the unsoundness explicit and isolated in one tiny component
- provides the target of generated placeholder applications

This file is intentionally minimal so the rest of the layer can depend on it cheaply.

### `AFTK/Informal/Options.lean`

This file registers the Lean option:

```text
aftk.informal.root
```

Implementation role:

- lets Lean elaboration choose a knowledge-base root without hard-coding one
- is reused by the server worker when producing richer hover for `informal[...]`

This is the main bridge between elaboration-time configuration and knowledge-base resolution.

### `AFTK/Informal/References.lean`

This file owns the typed notion of an informal reference and how it resolves through the knowledge base.

Key types:

- `InformalReference`
- `ResolvedInformalReference`

Key functions:

- `InformalReference.ofNodeId`
- `InformalReference.ofString?`
- `InformalReference.render`
- `InformalReference.startsWithSegmentPrefix`
- `informalReferenceOfString?`
- `resolveInformalReferenceIn`
- `resolveInformalReferenceAtRoot`
- `resolveInformalReference`

Implementation role:

- validates raw strings against knowledge-base node-id rules
- stores references in a small typed wrapper instead of as raw strings
- delegates actual node loading to `AFTK.KnowledgeBase.Storage`

Boundary worth preserving:

- `InformalReference` stores identity only
- `ResolvedInformalReference` carries loaded knowledge-base data
- canonical prose still belongs to the knowledge-base layer

### `AFTK/Informal/Tracking.lean`

This file implements persistent declaration-level tracking of successful informal references.

Key types:

- `InformalOccurrence`
- `InformalDeclEntry`
- `InformalReferenceEntry`

Key functions:

- `addInformalOccurrence`
- `allInformalDeclEntries`
- `informalDeclEntry?`
- `allInformalReferenceEntries`
- `informalReferenceEntry?`

Implementation role:

- records declaration→reference occurrences in a `SimplePersistentEnvExtension`
- deduplicates repeated references within one declaration at the public query layer
- derives reverse reference→declaration views on demand
- merges data across imported modules when environments are loaded with `loadExts := true`

This is the durable bridge metadata of the informal layer.
It is not a second copy of knowledge-base metadata.

### `AFTK/Informal/Dependencies.lean`

This file computes dependency projections from Lean environments and tracking data.

Key types:

- `InformalDeclDependencyEntry`
- `InformalReferenceDependencyEntry`

Key functions:

- `allInformalDeclDependencyEntries`
- `informalDeclDependencyEntry?`
- `informalDeclDependencyLeaves`
- `allInformalReferenceDependencyEntries`
- `informalReferenceDependencyEntry?`
- `informalReferenceDependencyLeaves`

Implementation role:

- uses Lean used-constant information to compute declaration reachability
- continues traversing through untracked declarations internally
- filters public rows down to tracked declarations/references
- projects declaration dependencies into reference dependencies
- handles cycles with a visited set

This component is deliberately derived and query-oriented.
It does not persist a canonical graph.

### `AFTK/Informal/Presentation.lean`

This file owns rendering-friendly views over resolved references.

Key types:

- `InformalPresentationSummary`
- `InformalBodyPresentation`
- `InformalPresentationPayload`
- `PresentationMode`
- `BodyRenderMode`

Key functions:

- `summaryOfResolved`
- `payloadOfResolved`
- `renderSummaryText`
- `renderPayloadText`
- `renderPresentationText`

Implementation role:

- turns resolved knowledge-base data into compact or rich informal presentation
- applies deterministic sorting for tags/authors/relationships/Lean refs
- implements body policies `.none`, `.preview`, and `.full`
- provides reusable text rendering for the CLI and server hover integration

This is the main presentation boundary consumed by higher layers.

### `AFTK/Informal/Elaborator.lean`

This file implements the actual term elaborator for `informal[...]`.

Implementation role:

- recognizes parsed `informal[...]` syntax
- recovers the enclosing declaration context
- rejects pseudo-declaration contexts like `_check`-style generated contexts
- resolves the reference through the knowledge base
- determines the result type from the expected type or a fresh metavariable
- builds an `Informal` placeholder expression
- generates a site-unique tag using source-location information when available
- attaches compact summary text to the info tree
- records tracking only after successful elaboration

This file is the semantic center of the layer.
It is where syntax, knowledge-base resolution, placeholder construction, info-tree enrichment, and tracking come together.

## CLI component details

### `AFTK/Informal/Cli/Types.lean`

This file defines the internal command model for the informal CLI.

Key definitions:

- `OutputFormat`
- `DepsMode`
- `PresentMode`
- `GlobalOptions`
- `DeclsOptions`
- `RefsOptions`
- `DepsOptions`
- `PresentOptions`
- `Command`
- `HelpTopic`
- `StatusResult`
- `CommandResult`

Implementation role:

- gives the parser a typed command target
- distinguishes environment-backed commands from direct presentation commands
- gives the renderer a stable result space

### `AFTK/Informal/Cli/Parse.lean`

This file turns argv into `GlobalOptions × Command`.

Key responsibilities:

- parse repeatable `--module <Module.Name>` imports
- parse `--root` and `--format`
- enforce which options are legal for which commands
- parse declaration names and node-id references
- require `--module` for environment-backed commands
- detect help topics before execution

Useful functions to read:

- `parseHelpTopic?`
- `parseArgs`
- `ensureModulesIfNeeded`

Implementation style:

- hand-written parser
- usage failures become `KnowledgeBaseError.usage`
- both `--help` and `-h` participate in help detection

### `AFTK/Informal/Cli/Render.lean`

This file renders help text and command results.

Key responsibilities:

- compact text rendering for status, decls, refs, deps, and present
- command-shaped JSON success rendering
- structured JSON failure rendering
- command-specific help text

Useful functions to read:

- `renderHelp`
- `renderSuccess`
- `renderFailure`

Implementation detail worth knowing:

- unlike the knowledge-base CLI, informal success JSON is command-shaped rather than wrapped in a common `ok/result` envelope

### `AFTK/Informal/Cli/Main.lean`

This file wires environment import, command dispatch, and rendering together.

Key functions:

- `run`
- `main`
- `importEnvironment`
- `runCoreInEnv`
- `commandResultInEnv`
- `presentResult`
- `commandResult`

Implementation role:

- imports Lean modules with `loadExts := true` so tracking data is available
- runs tracking/dependency queries in `CoreM`
- resolves `present` directly through the knowledge base instead of through imported tracking state
- maps not-tracked failures to `KnowledgeBaseError.notFound`
- prints text failures to stderr and JSON failures to stdout

This file is the best code pointer for the real behavior of `lake exe aftk_cli informal ...`.

## Actual call flows

### Elaboration flow

The core elaboration path is:

1. `Syntax.lean` parses `informal[...]`
2. `Elaborator.lean` extracts the raw reference text
3. `References.lean` validates and resolves it through the knowledge base
4. `Placeholder.lean` supplies the `Informal` primitive used to build the term
5. `Presentation.lean` creates a compact summary for the info tree
6. `Tracking.lean` records the declaration/reference association

This is the key implementation story of the whole layer.

### CLI flow

The command-line path is:

1. `Main.lean` dispatches `aftk informal ...` to `AFTK.Informal.Cli.Main.main`
2. `Cli.Parse.parseHelpTopic?` handles help requests
3. `Cli.Parse.parseArgs` builds `GlobalOptions × Command`
4. `Cli.Main.commandResult` either:
   - imports modules and runs tracking/dependency queries, or
   - resolves `present` directly through the knowledge base
5. `Cli.Render.renderSuccess` or `Cli.Render.renderFailure` prints the result

## Good extension points

If you are extending the layer, prefer these boundaries:

- syntax changes: `Syntax.lean`
- configuration/root changes: `Options.lean`
- knowledge-base resolution behavior: `References.lean`
- tracking semantics: `Tracking.lean`
- dependency algorithms: `Dependencies.lean`
- rich/compact rendering: `Presentation.lean`
- elaboration behavior: `Elaborator.lean`
- new CLI subcommands: `Cli/Types.lean`, `Cli/Parse.lean`, `Cli/Main.lean`, `Cli/Render.lean`

## Related docs

- `docs/informal/overview.md`
- `docs/informal/cli.md`
- `docs/informal/testing.md`
