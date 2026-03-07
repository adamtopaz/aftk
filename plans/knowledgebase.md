# Knowledge Base Layer Plan

## Status

Overall plan for the first layer of the `aftk` rewrite.
This document is intentionally architectural and serves as the top-level plan for the knowledge base layer.
Detailed subdesigns should live in component plan files under `plans/knowledgebase/`.

## Plan implementation status

- Overall status: Not implemented
- Fully implemented: No
- Last updated basis: overall plan plus metadata and node component designs

This section is the single place for tracking whether the knowledge base layer plan has been fully implemented.
It should be updated whenever the implementation meaningfully changes.

A practical definition of fully implemented for this plan is:

- the knowledge base layer exists in code
- the initial `lake exe aftk kb ...` CLI surface exists
- core node and metadata operations are implemented
- relationship-aware metadata is supported
- basic validation and discovery functionality is implemented
- the remaining items in the implementation-progress checklist are either complete or intentionally deferred with notes

## Purpose

The knowledge base layer is the foundation of the new architecture.
Its job is to store, organize, retrieve, and search natural-language mathematical and technical knowledge.

The most important architectural commitment of the rewrite is:

> The knowledge base is the single source of truth for natural-language knowledge.

Higher layers may reference, elaborate, transform, or act on that knowledge, but they should not introduce competing natural-language storage systems.

## Position in the layered architecture

The overall rewrite stack is:

1. Knowledge base layer
2. Informal layer
3. Server and file-worker layer
4. Toolkit layer
5. AI autoformalization agent layer

The knowledge base layer sits at the bottom of this stack.
Everything above it depends on it directly or indirectly.

## Core responsibilities

The knowledge base layer should provide the following capabilities:

- create natural-language knowledge entries
- read and inspect existing entries
- modify existing entries
- attach and maintain structured metadata
- represent relationships between knowledge-base nodes
- search across the corpus
- support querying and filtering over metadata, content, and relationships
- provide stable references that higher layers can depend on
- expose these capabilities through Lean-native tooling

This layer is not just a passive file store.
It is the system boundary for managing natural-language knowledge in a structured, queryable way.

## Architectural commitments

### 1. Single source of truth for natural-language content

Natural-language knowledge should live in exactly one place in the rewritten system: the knowledge base.

This means, for example, that the later informal layer should refer to knowledge-base nodes rather than storing separate copies of the same prose.

### 2. Human-readable primary content

Main content should be stored in Markdown.
This keeps the core knowledge easy to read, review, diff, and edit by humans.

### 3. Machine-readable structured metadata

Metadata should be stored in JSON.
This gives higher layers and automation tools a reliable format for structured inspection, filtering, validation, and indexing.

### 4. Relationship-aware metadata

Knowledge-base metadata should support explicit relationships between nodes.
That allows the layer to represent cross-references, dependencies, refinement links, examples, prerequisites, and other semantic connections in a structured way.

This does not require the first implementation to be a full graph database.
However, the metadata model should be designed so that the knowledge base can naturally be treated as a knowledge graph when needed.

### 5. Lean-native core interface

The primary interface to the knowledge base should be a Lean-based CLI:

```text
lake exe aftk kb ...
```

This keeps the core of the system Lean-native and ensures that the knowledge base integrates cleanly with the rest of the lower-level architecture.

### 6. File-backed and inspectable storage

The knowledge base should remain transparent and inspectable at the filesystem level.
Even when richer indexing or search infrastructure is added later, the canonical representation should remain understandable and editable in ordinary files.

## Conceptual model

The central object in this layer is a **knowledge-base node**.

A node represents one unit of natural-language knowledge, such as:

- a definition
- a theorem statement in informal form
- an explanation
- a proof sketch
- a concept note
- a worked example
- a technical note
- a cross-referenceable documentation unit

At a high level, each node should have:

- an identity
- Markdown content
- JSON metadata
- zero or more relationships to other nodes, represented through metadata

The conceptual split is already clear:

- **Markdown** holds the main human-facing content
- **JSON** holds structured metadata about that content

The node-level pairing and naming design is captured in `plans/knowledgebase/node.md`.
The broader knowledge-base root directory and repository layout remain to be refined.

## Component plans

The following component plans refine parts of the knowledge base layer design:

- `plans/knowledgebase/metadata.md` — initial Lean metadata type design and JSON representation
- `plans/knowledgebase/node.md` — node identity, Markdown/JSON pairing, and node-level invariants

Likely future component plans include:

- knowledge-base directory and file layout
- CLI command structure
- validation behavior
- search behavior

## Primary operations

The knowledge base CLI should eventually support operations in categories like these:

### Content management

- create a node
- update a node
- rename or move a node
- delete a node if deletion is supported
- view a node
- list nodes

### Metadata management

- inspect metadata
- edit metadata
- validate metadata
- query by metadata fields

### Discovery

- full-text search
- tag/category search
- related-node traversal
- listing/filtering/sorting operations

### Integrity and maintenance

- validation of node structure
- detection of broken references
- indexing or reindexing support
- consistency checks between content and metadata

## Relationship to higher layers

The knowledge base layer should be designed so that higher layers can rely on it without reimplementing its logic.

### Informal layer

The informal layer should reference knowledge-base nodes directly.
For example, a construct like `informal[a.b.c]` should resolve through the knowledge base rather than through a separate informal-content store.

### Server and file-worker layer

The server and file-worker should be able to inspect and operate on knowledge-base content as part of their broader service role.

### Toolkit and AI agent layers

TypeScript tools and AI agents should consume stable knowledge-base operations through the lower-level interfaces, rather than bypassing the layer with ad hoc file conventions.

## Boundaries and non-goals

The knowledge base layer is foundational, but it should still have a clear scope.

### In scope

- canonical storage of natural-language knowledge
- structured metadata
- querying and search
- CLI-driven management of knowledge nodes
- stable references for other layers

### Out of scope for this layer

- Lean elaboration behavior itself
- `informal[...]` semantics beyond the fact that they reference KB nodes
- server orchestration concerns
- TypeScript toolkit abstractions
- AI-agent workflow logic

Those belong to later layers.

## Design constraints

As more detailed designs are written, the knowledge base layer should preserve the following constraints:

- canonical data should stay file-backed
- content should remain easy for humans to edit directly
- metadata should remain predictable for programs to consume
- node identities should be stable enough for references from other layers
- the interface should be suitable for automation as well as manual use
- the design should support growth into search, indexing, and agent workflows

## Questions to refine in follow-up component plans

This overview leaves several important questions open for later design documents:

- What is the exact knowledge-base root directory and broader file layout?
- What metadata fields are required, optional, or derived beyond the initial metadata type?
- What validation rules should the CLI enforce?
- How should search behave initially, and how might it evolve later?
- How should links and references between nodes be represented at the filesystem and CLI levels beyond the basic node model?
- What operations should be atomic from the CLI’s point of view?
- What parts of the implementation should be pure Lean, and what parts may rely on supporting libraries or tools?

## Immediate implementation direction

The first implementation work for this layer should likely focus on:

1. choosing the knowledge-base root directory and minimal storage layout
2. implementing the initial node and metadata types plus their JSON/path mappings
3. creating the initial `lake exe aftk kb ...` command surface
4. supporting basic create/read/update/list operations
5. adding simple validation and search
6. refining the design where implementation pressure reveals missing details

That would establish a usable base layer without prematurely fixing every advanced feature.

## Implementation progress

This section tracks implementation progress for the knowledge base layer plan.
It should be updated as design decisions are made and code lands.

### Planning and design

- [x] Create the overall knowledge base layer plan
- [ ] Define the knowledge-base directory and file layout
- [x] Define node identity and naming conventions (`plans/knowledgebase/node.md`)
- [x] Define the initial Markdown + JSON pairing model (`plans/knowledgebase/node.md`)
- [x] Define the initial metadata schema (`plans/knowledgebase/metadata.md`)
- [x] Define how node-to-node relationships are represented in metadata (`plans/knowledgebase/metadata.md`)
- [ ] Add follow-up component plans for layout and CLI design

### Lean CLI surface

- [ ] Add the top-level `lake exe aftk kb ...` command entry point
- [ ] Define the initial subcommand structure
- [ ] Implement `create`
- [ ] Implement `read`/`show`
- [ ] Implement `list`
- [ ] Implement `update`
- [ ] Implement metadata inspection/editing commands

### Validation and discovery

- [ ] Implement metadata validation
- [ ] Implement node structure validation
- [ ] Implement basic full-text search
- [ ] Implement metadata-based query/filter support
- [ ] Implement relationship traversal/query support
- [ ] Implement broken-reference detection

### Integration readiness

- [ ] Provide stable node references for higher layers
- [ ] Document assumptions needed by the informal layer
- [ ] Document assumptions needed by the server/file-worker layer

### Notes

- Current state: planning, metadata design, and node design only
- No knowledge base implementation has been landed yet
- The initial metadata type design is now captured in `plans/knowledgebase/metadata.md`
- The initial node design is now captured in `plans/knowledgebase/node.md`
- This checklist is intentionally high-level and can be refined into smaller tasks later

## Summary

The knowledge base layer is the foundational data layer of the `aftk` rewrite.
It owns all natural-language knowledge in the system, stores main content in Markdown, stores structured metadata in JSON, and exposes Lean-native CLI operations for creating, editing, querying, and searching that knowledge.

Everything built later in the rewrite should treat this layer as the canonical source of natural-language information.