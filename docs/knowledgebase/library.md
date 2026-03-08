# Knowledgebase Lean library

Import the public library root with:

```lean
import AFTK.KnowledgeBase
```

## Module layout

Current module structure:

```text
AFTK/KnowledgeBase/Types.lean
AFTK/KnowledgeBase/PathLayout.lean
AFTK/KnowledgeBase/Serialization.lean
AFTK/KnowledgeBase/Storage.lean
AFTK/KnowledgeBase/Validation.lean
AFTK/KnowledgeBase/Search.lean
AFTK/KnowledgeBase/Repair.lean
AFTK/KnowledgeBase/Indexing.lean
AFTK/KnowledgeBase/Cli/Types.lean
AFTK/KnowledgeBase/Cli/Parse.lean
AFTK/KnowledgeBase/Cli/Render.lean
AFTK/KnowledgeBase/Cli/Main.lean
```

The reusable library lives outside `Cli/`.

## Core types

### Identity and timestamps

- `NodeId`
- `Timestamp`

### Metadata and graph structure

- `NodeKind`
- `NodeStatus`
- `RelationshipKind`
- `Relationship`
- `LeanDeclRef`
- `NodeMetadata`

### Stored nodes and storage layout

- `Node`
- `NodePaths`
- `StoredNode`
- `DiscoveredNodeFiles`
- `StorageManifest`
- `KnowledgeBaseStoragePaths`

### Errors and monads

- `KnowledgeBaseError`
- `KBIO := EIO KnowledgeBaseError`

## Important namespaces

### `AFTK.KnowledgeBase.PathLayout`

Key helpers:

- `resolveRootPath`
- `storagePathsForRoot`
- `nodeIdToRelativeStem`
- `nodePaths`
- `pathStemToNodeId?`
- `nodeIdFromNodeFilePath?`

### `AFTK.KnowledgeBase.Serialization`

Key helpers:

- `renderStorageManifest`
- `renderNodeMetadata`
- `parseStorageManifestText`
- `parseNodeMetadataText`
- `normalizeMarkdownForRead`
- `normalizeMarkdownForWrite`

### `AFTK.KnowledgeBase.Storage`

Key operations:

- `initRoot`
- `resolveInitializedRoot`
- `loadStoredNode`
- `createNode`
- `setNodeBody`
- `replaceNodeMetadata`
- `renameNode`
- `deleteNode`
- `scanCanonicalNodeFiles`
- `loadAllStoredNodes`
- `loadAllMetadata`

### `AFTK.KnowledgeBase.Validation`

Key operations:

- `validateStorage`
- `validateMetadata`
- `validateNode`
- `validateAll`

Key types:

- `ValidationSeverity`
- `ValidationScope`
- `ValidationIssue`
- `ValidationReport`

### `AFTK.KnowledgeBase.Search`

Key operations:

- `searchText`
- `searchTag`
- `outgoingRelationships`
- `incomingRelationships`
- `relatedRelationships`

## Example: creating and loading a node

```lean
import AFTK.KnowledgeBase

open AFTK.KnowledgeBase
open AFTK.KnowledgeBase.PathLayout

#eval do
  let root ← PathLayout.resolveRootPath (some "knowledgebase")
  let paths ← (Storage.initRoot root).toIO'  -- or handle the `KBIO` result explicitly
  pure ()
```

In practice, callers will usually handle `KBIO` values by converting them with `toIO'` or adapting the `KnowledgeBaseError` value into a higher-layer error type.

## Assumptions for higher layers

The current implementation is intended to be consumed with these assumptions:

- `NodeId` is the stable cross-layer reference for prose knowledge
- Markdown + JSON under canonical storage remain the source of truth
- higher layers should not bypass validation by inventing parallel storage conventions
- direct scans are semantically authoritative even if indexing is added later

## Deferred APIs

`Repair` and `Indexing` currently contain scaffolding types only.
They are present to preserve the planned module shape, but operational repair and indexing workflows are still deferred.
