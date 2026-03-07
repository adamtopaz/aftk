# Knowledge Base Search Design

## Status

Design-only component plan for knowledge-base search.
This document refines the overall knowledge base plan in `plans/knowledgebase.md` and works together with `plans/knowledgebase/storage.md`, `plans/knowledgebase/node.md`, `plans/knowledgebase/metadata.md`, and `plans/knowledgebase/cli.md`.

## Component implementation status

- Overall status: Not implemented
- Implemented in code: No
- Last updated basis: design only

## Purpose

This document defines the search model for the knowledge base layer.
It describes what should be searchable, how initial search behavior should work, how search should relate to canonical versus derived data, and how search should connect to the CLI.

No code is being added yet.
This file is only a design target for later implementation.

## Design goals

Search should:

- work over canonical knowledge-base content
- support both content search and metadata-driven search
- return stable node IDs as the primary results
- be useful interactively while also supporting automation
- remain correct even if no derived index exists yet
- allow later performance improvements through rebuildable indexes
- align with the relationship-aware metadata model

Lean module and namespace naming for this layer should use `KnowledgeBase` rather than `KB`.
The public CLI should use `lake exe aftk knowledgebase ...`.

## Search principles

### 1. Canonical data is the search truth

Search semantics should be defined in terms of canonical files:

- Markdown bodies under `knowledgebase/nodes/**`
- JSON metadata under `knowledgebase/nodes/**`

Derived indexes may improve performance, but they should not redefine what search means.

### 2. Search results are node-centric

The main result of a search should be one or more knowledge-base nodes.
Even if matching happens against text snippets, metadata fields, or relationship information, the user-facing result should center on node IDs.

### 3. Initial search should be simple and predictable

The first implementation should prefer clear, explainable behavior over sophisticated ranking.
A straightforward search that is correct is better than a clever search that is hard to reason about.

### 4. Search and query are related but not identical

Some commands are really search-like discovery commands, while others are more structured queries over metadata.
The CLI can expose both under the `search` family initially as long as the semantics stay explicit.

## Searchable data sources

The search system should eventually be able to consider these sources.

### 1. Markdown body text

This is the most important full-text source.
It should support content discovery in the main prose of nodes.

### 2. Metadata fields

Certain metadata fields should be directly searchable or filterable, especially:

- `id`
- `title`
- `summary`
- `tags`
- `kind`
- `status`
- `authors`

### 3. Relationships

Relationship metadata should support search or query patterns such as:

- nodes pointing to a target
- nodes with outgoing edges of a given kind
- nodes related to a target node

The first implementation does not need advanced graph search, but the design should leave room for it.

## Initial search modes

The CLI plan already proposes a small initial `search` family.
This document makes those modes more precise.

### `search text <query>`

This is the basic full-text search command.
Initial semantics should be:

- search Markdown body text
- optionally include selected textual metadata fields such as `title` and `summary`
- return matching nodes
- prefer simple substring or token-based matching in v1

The first implementation does not need stemming, fuzzy search, or advanced ranking.

### `search tag <tag>`

This is a structured metadata search over the `tags` field.
Initial semantics should be:

- exact tag match
- return nodes carrying that tag

This should be easy to implement and very useful in practice.

## Likely near-term extensions

Once the basic search modes exist, the next useful additions would likely be:

- `search title <query>`
- `search prefix <node-id-prefix>`
- `search kind <kind>`
- `search status <status>`
- `search author <author>`
- `search related <id>`

These extensions are not required for the first implementation, but the design should make room for them.

## Query/filter model

Some search behavior is really filtering over known structured fields.
A practical design for the layer is:

- **text search** for unstructured discovery
- **metadata filters** for structured discovery
- **relationship traversal** for graph-aware discovery

That suggests the system should eventually support an internal search request model rather than encoding everything as ad hoc command cases.

### Proposed Lean-level types

```lean
namespace AFTK.KnowledgeBase

inductive SearchScope
  | bodyText
  | title
  | summary
  | tags
  | metadata
  | allText

inductive SearchFilter
  | kind (value : NodeKind)
  | status (value : NodeStatus)
  | tag (value : String)
  | author (value : String)
  | idPrefix (value : String)

structure SearchRequest where
  query? : Option String := none
  scopes : Array SearchScope := #[]
  filters : Array SearchFilter := #[]
  limit? : Option Nat := none

structure SearchHit where
  id : NodeId
  score? : Option Float := none
  title? : Option String := none
  summary? : Option String := none
  matchedScopes : Array SearchScope := #[]
  snippet? : Option String := none

structure SearchResult where
  hits : Array SearchHit := #[]

end AFTK.KnowledgeBase
```

This is only a conceptual design.
The initial CLI can implement a smaller subset while still evolving toward this model.

## Search result expectations

A search result should generally include:

- the matched node ID
- enough descriptive text to identify the result quickly
- optional snippet/highlight information for text search
- optional score or ordering metadata if ranking is used

The result should not force callers to parse free-form text to find the actual node IDs.

### Suggested text output style

For human output, each hit should ideally show:

- node ID
- title if available
- maybe kind/status/tag information
- a short snippet for text search

### Suggested JSON output style

For machine output, each hit should be structured explicitly with fields like:

- `id`
- `title`
- `summary`
- `matchedScopes`
- `snippet`
- `score`

## Search ordering

The initial implementation should keep ordering rules simple.

### For `search text`

A simple initial strategy could be one of:

- unsophisticated stable order by node ID
- stable order by path scan order
- lightweight ranking by number or quality of textual matches

If ranking is introduced, it should be shallow and explainable.
The design should not require advanced scoring in v1.

### For structured searches

For tag/kind/status/prefix-style queries, a stable deterministic order such as node ID order is preferable.

## Relationship-aware discovery

Because the knowledge base metadata is relationship-aware, search should eventually support graph-adjacent discovery patterns.
Examples:

- find all nodes that reference a target node
- find nodes with a particular relationship kind
- find nodes related to a given node

The CLI plan currently puts these mostly under `relationships ...` commands rather than `search ...` commands.
That is a good initial split.
However, internally, these features are closely related to search/query infrastructure.

## Indexing strategy

The first implementation should not depend on a prebuilt index.
A correct implementation may scan canonical files directly.

However, the storage design already reserves:

```text
knowledgebase/.aftk/index/
```

That means the search system should be designed with two modes in mind:

### Direct scan mode

- reads canonical Markdown and JSON files directly
- simplest and most trustworthy implementation
- suitable for initial correctness

### Indexed mode

- uses rebuildable derived search/index state
- improves performance for larger knowledge bases
- must preserve the same canonical search semantics

The existence or freshness of an index should not change the meaning of search results.

## CLI alignment

The CLI plan in `plans/knowledgebase/cli.md` proposes these initial commands:

- `lake exe aftk knowledgebase search text <query>`
- `lake exe aftk knowledgebase search tag <tag>`

That aligns well with the initial search design.
Future CLI additions might include:

- `search title <query>`
- `search kind <kind>`
- `search status <status>`
- `search author <author>`
- `search prefix <prefix>`

## Validation interaction

Search behavior should interact cleanly with validation.
For example:

- malformed metadata should ideally be surfaced by validation rather than causing mysterious search behavior
- search indexing, if present, should be rebuildable after validation/repair steps
- search should avoid silently trusting broken derived state over canonical data

## Recommended first implementation slice

The first search implementation should likely prioritize:

1. `search text <query>` over Markdown body plus lightweight textual metadata
2. `search tag <tag>` over exact metadata tags
3. deterministic text and JSON output
4. direct canonical-file scanning

After that, likely next steps are:

- additional metadata filters
- snippets/highlights
- relationship-aware discovery helpers
- rebuildable indexing support under `knowledgebase/.aftk/index/`

## Design decisions for v1

The initial search design intentionally does **not** require:

- fuzzy search
- stemming or linguistic normalization
- semantic embedding search
- advanced ranking heuristics
- approximate nearest-neighbor indexes
- graph path search beyond straightforward relationship traversal/query support

Those may become useful later, but v1 should focus on correctness, clarity, and simple discoverability.

## Open questions for later refinement

- Should text search include `title` and `summary` by default, or only Markdown body text?
- What snippet-generation behavior is best for readable text output?
- When should ranking be introduced, if at all?
- How much query composition should the first CLI expose?
- When should relationship-aware discovery move from separate traversal commands into richer query forms?

## Summary

The knowledge-base search system should be node-centric and defined in terms of canonical content.
It should begin with simple, correct search modes over Markdown and metadata, while leaving room for later indexed acceleration.

The initial CLI surface should focus on:

- `lake exe aftk knowledgebase search text <query>`
- `lake exe aftk knowledgebase search tag <tag>`

Search results should be structured around node IDs and should support both readable text output and stable JSON output for automation.