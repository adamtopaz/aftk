# Knowledge Base Node Design

## Status

Component plan and implementation-status document for knowledge-base nodes.
This document refines the overall knowledge base plan in `plans/knowledgebase.md` and complements `plans/knowledgebase/metadata.md`.

## Component implementation status

- Overall status: Implemented for the current v1 node model
- Implemented in code: Yes
- Last updated basis: current `NodeId`, `Node`, `NodePaths`, `StoredNode`, and storage invariants implemented in the knowledgebase library

## Purpose

This document defines what a knowledge-base node is, both as a logical object in Lean and as a file-backed object on disk.

The goal is to make node identity, Markdown/JSON pairing, and core node invariants explicit before implementation begins.

Code has now been added.
This file remains the design reference and status tracker for the implemented node model.

## Design goals

The node design should:

- give the knowledge base a clear unit of storage and reference
- separate semantic node identity from filesystem location details
- pair Markdown content and JSON metadata in a predictable way
- support direct filesystem inspection and editing
- align with the metadata type design
- make validation rules straightforward to express and enforce
- support future CLI operations such as create, read, body/metadata mutation, rename, and delete

Lean module and namespace naming for this layer should use `KnowledgeBase` rather than the abbreviation `KB`.
For example, the intended namespace is `AFTK.KnowledgeBase`.

## What a node is

A knowledge-base node is one unit of natural-language knowledge.

Examples include:

- a definition
- an informal theorem statement
- a proof sketch
- an explanation
- a worked example
- a concept note
- a technical note

A node has two canonical parts:

1. **Markdown body**: the main human-readable content
2. **JSON metadata**: structured information about the node

The Markdown body is where the primary prose lives.
The JSON metadata is where structured fields such as title, tags, status, relationships, and Lean references live.

## Logical node vs stored node

The design should distinguish between:

- the **logical node**, which is the semantic content
- the **stored node**, which is the logical node together with its on-disk file locations

This distinction is useful because a node’s identity should not be reduced to an arbitrary file path.
The canonical identity is the node ID, not whichever path happened to be used when loading it.

## Proposed Lean-level types

```lean
namespace AFTK.KnowledgeBase

abbrev Markdown := String

structure Node where
  metadata : NodeMetadata
  body : Markdown

structure NodePaths where
  markdownPath : System.FilePath
  metadataPath : System.FilePath

structure StoredNode where
  node : Node
  paths : NodePaths

end AFTK.KnowledgeBase
```

This design intentionally keeps the core node representation small:

- `Node` is the in-memory semantic object
- `NodePaths` describes where the two canonical files live
- `StoredNode` combines the semantic object with its storage location

The `NodeMetadata` type is defined in `plans/knowledgebase/metadata.md`.

## Node identity

Each node has a canonical `NodeId`.
That ID is the stable reference that higher layers should use.

The initial node-ID design should use a dotted namespace style such as:

- `group.basic.definition`
- `topology.open_cover`
- `analysis.uniform_continuity`

### Proposed naming rules

A `NodeId` should:

- be nonempty
- consist of dot-separated segments
- not begin or end with a dot
- not contain empty segments
- not contain path separators such as `/` or `\`
- not contain whitespace
- avoid special path-like fragments such as `.` and `..`

For the initial design, each segment should follow a conservative convention like:

- first character: lowercase ASCII letter
- remaining characters: lowercase ASCII letters, digits, or `_`

This gives the project a stable, predictable naming convention that is easy to map onto filesystem paths and easy to validate.

## On-disk representation

The initial design should represent each node as exactly two canonical files:

- one Markdown file
- one JSON metadata file

These files should be sibling files with the same basename.

### Canonical pairing rule

For a node with a storage stem `<stem>`, the canonical files are:

- `<stem>.md`
- `<stem>.json`

For example, if the stem is `topology/open_cover`, then the node files are:

- `topology/open_cover.md`
- `topology/open_cover.json`

This gives a simple, inspectable, file-backed pairing model.

## Mapping from node ID to path stem

The initial design should map node IDs to relative path stems as follows:

- split the node ID on `.`
- use all but the last segment as directories
- use the last segment as the basename

Examples:

- `topology.open_cover` -> `topology/open_cover`
- `group.basic.definition` -> `group/basic/definition`
- `analysis.uniform_continuity` -> `analysis/uniform_continuity`

This means the canonical stored files for `topology.open_cover` are:

- `topology/open_cover.md`
- `topology/open_cover.json`

This design fixes the node-level pairing and naming convention.
The overall knowledge-base root directory and broader storage layout are defined in `plans/knowledgebase/storage.md`.

## Core invariants

A valid node should satisfy the following invariants.

### Logical invariants

- `node.metadata.id` is the canonical identity of the node
- the Markdown body is not duplicated inside metadata
- relationships stored in metadata are interpreted as outgoing relationships from `node.metadata.id`
- the node body is plain Markdown text stored separately from metadata

### Storage invariants

- each stored node has exactly one canonical Markdown file and one canonical JSON metadata file
- the Markdown and JSON files for a node share the same relative stem
- the node ID implied by the canonical path stem matches `node.metadata.id`
- both files must exist together for a fully materialized stored node
- orphaned `.md` or `.json` files should be treated as validation failures or repair cases

## Lifecycle semantics

The node design should support the following operations conceptually.

### Create

Creating a node should create both canonical files:

- the Markdown body file
- the JSON metadata file

The new metadata must include the node’s canonical ID.

In v1, node creation should follow these defaults:

- an empty Markdown body is allowed
- the created Markdown file may therefore be empty aside from normal newline normalization
- `kind` defaults to `note` unless explicitly provided
- `status` defaults to `draft` unless explicitly provided
- `createdAt` and `updatedAt` should both be auto-populated to the creation timestamp

### Read

Reading a node should:

- resolve the canonical file pair
- load the Markdown body
- load and parse the JSON metadata
- validate basic pairing and identity invariants

### Update body

Updating the body should modify the Markdown file while preserving the node’s identity.
In v1, a body update should also refresh `updatedAt` in metadata to the current timestamp, creating that field if it was absent.

### Update metadata

Updating metadata should modify the JSON file while preserving node/body pairing invariants.
In v1, metadata mutation should preserve the node’s canonical ID; changing identity requires an explicit rename operation rather than an implicit metadata edit.
A metadata update should also refresh `updatedAt` to the current timestamp.

### Rename

Renaming a node should be treated as an identity-changing operation.
It should update:

- the node ID in metadata
- the canonical Markdown path
- the canonical JSON path

These updates should happen together as one logical operation.
A rename should also refresh `updatedAt` in the stored metadata.

### Delete

Deleting a node should remove both canonical files.

## Relationship to the metadata type

The node design depends on the metadata type design, but the two should remain conceptually separate:

- `NodeMetadata` describes structured facts about the node
- `Node` adds the Markdown body
- `StoredNode` adds filesystem location information

This separation should make implementation cleaner.
In particular, many operations can work on `Node` values in memory without caring yet about disk paths, while storage-oriented commands can work on `StoredNode`.

## Validation expectations

A node validator should eventually be able to check at least the following:

- the Markdown file exists
- the JSON metadata file exists
- the two files are correctly paired
- metadata parses according to the metadata schema
- the node ID is syntactically valid
- the node ID matches the canonical path-derived ID
- required metadata fields are present
- no illegal orphan or duplicate node-file pair exists for the same ID

Relationship-target existence checks can be layered on top of basic node validation rather than being required for every local node read.

## Design decisions for v1

The initial node design intentionally does **not** include:

- embedded metadata inside Markdown frontmatter
- a single combined file containing both content and metadata
- attachments or asset directories as part of the base node model
- alias nodes or redirect nodes
- generated or cached secondary node representations as canonical storage

Those may be considered later, but the initial design should stay simple: one Markdown file plus one JSON file per node.

## Lean 4 reuse findings

Research against `System.FilePath`, `IO.FS`, and `Lean.Util.Path` suggests several low-boilerplate implementation choices for nodes.

- `System.FilePath` already provides `parent`, `fileStem`, `extension`, `withExtension`, `addExtension`, `components`, `normalize`, and `/`; these cover most of the path-pairing logic for sibling `.md` and `.json` files.
- `IO.FS.readFile` and `IO.FS.writeFile` directly cover UTF-8 body IO for Markdown and metadata files.
- `System.FilePath.readDir` and `IO.FS.DirEntry.path` are enough for explicit canonical-tree scans when enumerating nodes.
- `Lean.Util.Path.modToFilePath` and `Lean.Util.Path.forEachModuleInDir` are strong reference points because node IDs follow a dotted, module-like namespace. If `NodeId` is internally represented by a validated wrapper around `Lean.Name`, these helpers could remove path-mapping boilerplate.
- `Lean.Name` already has component/root operations, but it should only be reused behind a `NodeId` wrapper because raw `Name` permits anonymous and numeric components that may not match the canonical storage policy for knowledge-base IDs.
- One caveat from the core IO API is that `System.FilePath.walkDir` follows symlinks. For strict canonical node traversal, explicit recursion over `readDir` is probably safer than blindly using `walkDir`.

## Open questions for later refinement

- Should rename operations preserve aliases or historical IDs later?
- Should nodes eventually support attachments or referenced local assets?

## Summary

A knowledge-base node should be modeled as a small semantic object with:

- a canonical ID in metadata
- a Markdown body
- a JSON metadata record

On disk, each node should be represented by a sibling file pair sharing a common stem:

- `.md` for main content
- `.json` for metadata

The node ID should follow a dotted namespace convention and map canonically to the file stem.
That gives the knowledge base a clear storage unit, stable references, and straightforward validation rules.