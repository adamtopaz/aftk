# Knowledge-base implementation guide

This document is the component-level implementation map for the knowledge-base layer.
It describes how the current Lean code is organized, what each component owns, and where to look in the codebase.

## Public entrypoints and code roots

Main code pointers:

- umbrella re-export: `AFTK.lean`
- knowledge-base public root: `AFTK/KnowledgeBase.lean`
- top-level CLI dispatch: `Main.lean`
- knowledge-base CLI implementation: `AFTK/KnowledgeBase/Cli/*`

The public library import is:

```lean
import AFTK.KnowledgeBase
```

The public CLI entrypoint is:

```text
lake exe aftk knowledgebase ...
```

## Component map

| Component | Main code | Responsibility |
| --- | --- | --- |
| Public root | `AFTK/KnowledgeBase.lean` | Re-exports the reusable knowledge-base modules |
| Core types | `AFTK/KnowledgeBase/Types.lean` | Node ids, metadata, relationships, manifest, errors, JSON instances |
| Path layout | `AFTK/KnowledgeBase/PathLayout.lean` | Canonical root/path computation and path↔id mapping |
| Serialization | `AFTK/KnowledgeBase/Serialization.lean` | Strict JSON parsing, canonical JSON rendering, Markdown normalization |
| Storage | `AFTK/KnowledgeBase/Storage.lean` | Root init, node load/create/update/rename/delete, canonical scanning |
| Validation | `AFTK/KnowledgeBase/Validation.lean` | Structured validation reports for storage, metadata, nodes, whole roots |
| Search | `AFTK/KnowledgeBase/Search.lean` | Direct-scan text/tag search and relationship queries |
| CLI command model | `AFTK/KnowledgeBase/Cli/Types.lean` | Parsed command AST, output/result types, help topics |
| CLI parser | `AFTK/KnowledgeBase/Cli/Parse.lean` | Argument parsing, option validation, help-topic detection |
| CLI renderer | `AFTK/KnowledgeBase/Cli/Render.lean` | Help text, text rendering, JSON envelopes |
| CLI dispatcher | `AFTK/KnowledgeBase/Cli/Main.lean` | Root resolution, command dispatch, exit-code behavior |

## Root and re-export surfaces

### `AFTK.lean`

Project-wide umbrella import.
It publicly re-exports:

- `AFTK.KnowledgeBase`
- `AFTK.Informal`
- `AFTK.Server`
- `AFTK.FileWorker`

This is useful for consumers that want the whole current Lean surface, but most knowledge-base users should prefer the narrower import:

```lean
import AFTK.KnowledgeBase
```

### `AFTK/KnowledgeBase.lean`

This file is a thin public root that re-exports:

- `Types`
- `PathLayout`
- `Serialization`
- `Storage`
- `Validation`
- `Search`

It does not re-export the CLI modules.
That separation keeps reusable library code distinct from command-line plumbing.

## Core component details

### `AFTK/KnowledgeBase/Types.lean`

This file defines the domain vocabulary of the layer.
Everything else depends on it.

Important types:

- `KnowledgeBaseError`
- `KBIO := EIO KnowledgeBaseError`
- `NodeId`
- `Timestamp`
- `NodeKind`
- `NodeStatus`
- `RelationshipKind`
- `Relationship`
- `LeanDeclRef`
- `NodeMetadata`
- `Node`
- `NodePaths`
- `StoredNode`
- `DiscoveredNodeFiles`
- `StorageManifest`
- `KnowledgeBaseStoragePaths`

Important implementation facts:

- `NodeId` validation happens structurally at construction time.
- `KnowledgeBaseError` carries both a machine-ish code and a CLI-facing exit code.
- `NodeMetadata` is the canonical metadata record used everywhere: storage, validation, search, CLI rendering, and higher-layer presentation.
- `leanRefs` is part of stored metadata, but the informal layer's declaration tracking is a separate implementation concern.

Use this component when you need stable, cross-module types.
Do not duplicate these definitions in higher layers.

### `AFTK/KnowledgeBase/PathLayout.lean`

This file owns the canonical filesystem model.
Higher layers should never reverse-engineer node paths manually.

Key functions:

- `resolveRootPath`
- `defaultManifest`
- `storagePathsForRoot`
- `nodeIdToRelativeStem`
- `nodePaths`
- `relativeToNodesDir?`
- `stemFromRelativeNodeFile?`
- `stemFromAbsoluteNodeFile?`
- `pathStemToNodeId?`
- `nodeIdFromNodeFilePath?`
- `discoveredPathId?`

Implementation role:

- decides where `manifest.json`, `nodes/`, and `.aftk/` live
- maps `group.basic.definition` to `nodes/group/basic/definition.{md,json}`
- recovers node ids from discovered canonical files during scans
- gives the CLI and the library a single source of truth for root/path semantics

If you are adding any feature that touches files, start here first.

### `AFTK/KnowledgeBase/Serialization.lean`

This file owns canonical parsing and rendering.
It is the boundary between typed Lean structures and on-disk text.

Key functions:

- `renderStorageManifest`
- `renderNodeMetadata`
- `parseStorageManifestJson`
- `parseStorageManifestText`
- `parseNodeMetadataJson`
- `parseNodeMetadataText`
- `normalizeLineEndings`
- `normalizeMarkdownForWrite`
- `normalizeMarkdownForRead`
- `readMarkdownFile`
- `writeMarkdownFile`
- `writeManifestFile`
- `writeMetadataFile`

Implementation role:

- keeps metadata parsing strict instead of permissive
- centralizes canonical JSON shape and omission policy
- normalizes Markdown reads/writes so storage semantics stay stable across platforms

This is storage serialization logic, not generic display formatting.
CLI text/JSON output lives elsewhere.

### `AFTK/KnowledgeBase/Storage.lean`

This is the operational heart of the knowledge-base layer.
It performs real filesystem mutations and loads typed nodes from canonical files.

Key functions:

- `initRoot`
- `loadManifestAt`
- `resolveInitializedRoot`
- `ensureInternalDirs`
- `nodeExists`
- `loadMetadataAtPath`
- `loadStoredNode`
- `createNode`
- `setNodeBody`
- `replaceNodeMetadata`
- `renameNode`
- `deleteNode`
- `scanCanonicalNodeFiles`
- `loadAllStoredNodes`
- `loadAllMetadata`

Implementation role:

- initializes `knowledgebase/` roots and reserved `.aftk/` subdirectories
- requires canonical file pairs for fully stored nodes
- performs node lifecycle operations against real `.md` and `.json` files
- scans the canonical tree directly instead of using an index

Important behavioral boundaries:

- `resolveInitializedRoot` is the normal gateway for commands that require a real initialized root
- `renameNode` and `deleteNode` operate on canonical files, not logical database rows
- current semantics come from direct filesystem reads, not from caches or indexes

### `AFTK/KnowledgeBase/Validation.lean`

This component turns structural/storage checks into explicit reports.
It is how the layer avoids silent repair or ad hoc warning strings.

Key types:

- `ValidationSeverity`
- `ValidationScope`
- `ValidationIssue`
- `ValidationReport`

Key functions:

- `validateStorage`
- `validateMetadata`
- `validateNode`
- `validateAll`

Implementation role:

- validates root structure and manifest assumptions
- validates metadata/body agreement for individual nodes
- aggregates whole-root issues into a stable report shape
- preserves warnings and infos even when the report is overall successful

This component is the reason the CLI can distinguish successful validation, warning-bearing validation, and error-bearing validation with a stable exit-code model.

### `AFTK/KnowledgeBase/Search.lean`

This component implements the current discovery/query surface.
It is intentionally simple and index-free.

Key types:

- `SearchScope`
- `SearchHit`
- `SearchResult`
- `IncomingRelationship`
- `RelatedRelationships`

Key functions:

- `searchText`
- `searchTag`
- `outgoingRelationships`
- `incomingRelationships`
- `relatedRelationships`

Implementation role:

- walks loaded metadata/body content directly
- performs exact-tag matching
- computes incoming relationships by scanning other nodes' outgoing relationships
- exposes a combined related-relationship view for callers that want both directions

If future indexing is added, this component is the natural abstraction boundary to preserve.

## CLI component details

### `AFTK/KnowledgeBase/Cli/Types.lean`

This file defines the internal command model for the CLI.
It is the typed AST between parsing and execution.

Key definitions:

- `OutputFormat`
- `InputSource`
- `ShowSelection`
- `GlobalOptions`
- `ListOptions`
- `CreateOptions`
- `BodyCommand`
- `MetadataCommand`
- `ValidateCommand`
- `SearchCommand`
- `RelationshipCommand`
- `Command`
- `HelpTopic`
- `StatusInfo`
- `CommandResult`

Implementation role:

- gives the parser a strongly typed target
- gives the renderer a strongly typed result space
- keeps command execution independent of raw argv strings

### `AFTK/KnowledgeBase/Cli/Parse.lean`

This file turns argv into the command model.

Key responsibilities:

- parse global options like `--root` and `--format`
- validate node ids, kinds, statuses, and search limits early
- enforce per-command option rules
- detect contextual help topics such as `search text --help`

Useful functions to read:

- `parseHelpTopic?`
- `parseArgs`
- `parseGlobalOptions`
- `parseCommand`

Implementation style:

- argument parsing is handwritten and explicit
- usage failures become `KnowledgeBaseError.usage`
- help detection happens before ordinary command execution

### `AFTK/KnowledgeBase/Cli/Render.lean`

This file renders both help text and command results.

Key responsibilities:

- text rendering for each `CommandResult`
- JSON rendering for each `CommandResult`
- consistent success/failure envelopes in JSON mode
- per-topic help text generation

Useful functions to read:

- `renderHelp`
- `renderSuccess`
- `renderFailure`

Implementation detail worth knowing:

- knowledge-base JSON success output uses a stable envelope with command/root/ok/result/warnings-style structure
- this rendering policy is specific to the knowledge-base CLI and is separate from canonical metadata serialization in `Serialization.lean`

### `AFTK/KnowledgeBase/Cli/Main.lean`

This file wires parsing, dispatch, rendering, and exit codes together.

Key functions:

- `run`
- `main`
- internal `dispatch`
- internal `statusInfoForRoot`

Implementation role:

- resolves the effective root path
- allows `status` to probe uninitialized roots
- requires initialization for ordinary mutating/query commands
- dispatches into `Storage`, `Validation`, and `Search`
- maps validation failure to exit code `4`
- prints text failures to stderr and JSON failures to stdout

This is the best file to read if you want the real command-execution path.

## Actual call flows

### Library flow for one node lookup

Typical path through the code:

1. build/validate a `NodeId` in `Types.lean`
2. resolve storage paths in `PathLayout.lean`
3. parse metadata and body through `Serialization.lean`
4. load the typed `StoredNode` in `Storage.lean`
5. optionally validate or search using `Validation.lean` / `Search.lean`

### CLI flow

Actual command flow is:

1. `Main.lean` dispatches `aftk knowledgebase ...` to `AFTK.KnowledgeBase.Cli.Main.main`
2. `Cli.Parse.parseHelpTopic?` checks for help handling
3. `Cli.Parse.parseArgs` builds `GlobalOptions × Command`
4. `Cli.Main.dispatch` runs the command through library code
5. `Cli.Render.renderSuccess` or `Cli.Render.renderFailure` prints the result

That split is deliberate:

- parsing is isolated in `Cli/Parse.lean`
- execution is isolated in `Cli/Main.lean`
- display logic is isolated in `Cli/Render.lean`

## Good extension points

If you are extending the layer, prefer these boundaries:

- new filesystem semantics: `PathLayout.lean` or `Storage.lean`
- new canonical metadata fields: `Types.lean` plus `Serialization.lean` and `Validation.lean`
- new query commands: `Search.lean` plus CLI plumbing
- new CLI subcommands: `Cli/Types.lean`, `Cli/Parse.lean`, `Cli/Main.lean`, `Cli/Render.lean`

## Related docs

- `docs/knowledgebase/overview.md`
- `docs/knowledgebase/storage.md`
- `docs/knowledgebase/cli.md`
- `docs/knowledgebase/testing.md`
