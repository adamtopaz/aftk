# Knowledge-base Lean library

Import the public library root with:

```lean
import AFTK.KnowledgeBase
```

This re-exports the currently implemented reusable modules:

- `Types`
- `PathLayout`
- `Serialization`
- `Storage`
- `Validation`
- `Search`

The CLI modules live separately under `AFTK/KnowledgeBase/Cli/*`.

## Core types

### Errors and effect type

The library uses a small structured error type:

- `KnowledgeBaseError`
- `KBIO := EIO KnowledgeBaseError`

Important `KnowledgeBaseError` constructors/helpers:

- `KnowledgeBaseError.generic`
- `KnowledgeBaseError.usage`
- `KnowledgeBaseError.notFound`
- `KnowledgeBaseError.validation`
- `KnowledgeBaseError.conflict`

The error value also carries the CLI-oriented exit code.

### Identity and time

- `NodeId`
- `Timestamp`

Useful helpers:

- `NodeId.ofString?`
- `NodeId.segments`
- `NodeId.startsWithSegmentPrefix`
- `Timestamp.ofString?`
- `Timestamp.now`

### Metadata and graph structure

- `NodeKind`
- `NodeStatus`
- `RelationshipKind`
- `Relationship`
- `LeanDeclRef`
- `NodeMetadata`

Useful `NodeMetadata` helpers:

- `NodeMetadata.withUpdatedAt`
- `NodeMetadata.withId`
- `NodeMetadata.hasTag`
- `NodeMetadata.titleOrId`

### Node and storage records

- `Node`
- `NodePaths`
- `StoredNode`
- `DiscoveredNodeFiles`
- `StorageManifest`
- `KnowledgeBaseStoragePaths`

## Module guide

### `AFTK.KnowledgeBase.Types`

This module defines the domain types and JSON instances used throughout the layer.

A few implementation details worth knowing:

- `NodeId` is validated structurally at construction time
- `Timestamp` uses a strict `YYYY-MM-DDTHH:MM:SSZ` string representation
- metadata JSON instances omit defaults and empty arrays in canonical output

### `AFTK.KnowledgeBase.PathLayout`

This module owns path computation and path-to-id conversions.

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

Use this module whenever you need canonical path behavior.
Do not rebuild id/path logic ad hoc in higher layers.

### `AFTK.KnowledgeBase.Serialization`

This module owns canonical manifest/metadata rendering and strict parsing.

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

This is canonical serialization logic, not generic CLI rendering.

### `AFTK.KnowledgeBase.Storage`

This module provides the main filesystem operations.

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

Use `resolveInitializedRoot` in callers that need a validated root plus canonical storage paths.

### `AFTK.KnowledgeBase.Validation`

This module implements explicit reports rather than throwing ad hoc errors for whole-root checks.

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

A `ValidationReport` is considered successful when it contains no error-severity issue.
Warnings and infos are preserved structurally.

### `AFTK.KnowledgeBase.Search`

This module implements the current direct-scan discovery surface.

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

The current implementation is intentionally simple and index-free.

## Library usage patterns

### Resolve a root and load one node

```lean
import AFTK.KnowledgeBase

open AFTK.KnowledgeBase
open AFTK.KnowledgeBase.PathLayout

#eval do
  let root ← PathLayout.resolveRootPath (some "knowledgebase")
  let result ← (do
    let (paths, _) ← Storage.resolveInitializedRoot root
    let id ←
      match NodeId.ofString? "topology.open_cover" with
      | .ok id => pure id
      | .error err => throw <| KnowledgeBaseError.validation "node.invalidId" err
    Storage.loadStoredNode paths id).toIO'
  match result with
  | .ok stored =>
      IO.println stored.node.metadata.title
  | .error err =>
      IO.eprintln s!"{err.code}: {err.message}"
```

### Run a direct validation pass

```lean
#eval do
  let root ← AFTK.KnowledgeBase.PathLayout.resolveRootPath (some "knowledgebase")
  let report ← AFTK.KnowledgeBase.Validation.validateAll root
  IO.println s!"ok = {report.ok}, issues = {report.issues.size}"
```

## Assumptions higher layers should rely on

The current library is designed to expose these stable assumptions upward:

- `NodeId` is the cross-layer prose identifier
- canonical prose lives in Markdown + metadata JSON under the knowledge-base root
- direct scans define semantics even if indexing is added later
- higher layers should call library APIs instead of reverse-engineering the on-disk layout

## Deferred library areas

The public re-export surface does **not** currently include dedicated repair or indexing modules.
Those topics still exist only at the design/doc level.
