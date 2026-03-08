# Knowledge Base Metadata Type

## Status

Design-only component plan for the knowledge base metadata type.
This document refines the overall knowledge base plan in `plans/knowledgebase.md`.

## Component implementation status

- Overall status: Not implemented
- Implemented in code: No
- Last updated basis: design only

## Purpose

This document proposes the initial metadata model for knowledge-base nodes.
The intent is to implement this as an actual Lean type, while storing metadata on the filesystem as JSON.

No code is being added yet.
This file is only a design target for later implementation.

## Design goals

The initial metadata type should:

- be representable directly as Lean data types
- round-trip cleanly to and from JSON on disk
- support explicit node-to-node relationships
- be strict enough to validate reliably
- remain simple enough for humans to inspect and edit
- avoid duplicating the Markdown body inside metadata
- leave room for later schema evolution

Lean module and namespace naming for this layer should use `KnowledgeBase` rather than the abbreviation `KB`.
For example, the intended namespace is `AFTK.KnowledgeBase`.

## Proposed Lean-level types

```lean
namespace AFTK.KnowledgeBase

/-- Canonical knowledge-base node identifier, encoded in JSON as a string. -/
structure NodeId where
  value : String

/-- ISO-8601 timestamp string, validated separately. -/
structure Timestamp where
  value : String

inductive NodeKind
  | note
  | definition
  | theorem
  | proofSketch
  | example
  | explanation
  | concept
  | documentation

inductive NodeStatus
  | draft
  | active
  | deprecated
  | archived

inductive RelationshipKind
  | relatedTo
  | dependsOn
  | elaborates
  | refines
  | exampleOf
  | hasExample
  | seeAlso

structure Relationship where
  kind : RelationshipKind
  target : NodeId
  label? : Option String := none
  note? : Option String := none

structure LeanDeclRef where
  module? : Option String := none
  declaration : String
  kind? : Option String := none

structure NodeMetadata where
  schemaVersion : Nat := 1
  id : NodeId
  title : String
  kind : NodeKind := .note
  status : NodeStatus := .draft
  summary? : Option String := none
  tags : Array String := #[]
  authors : Array String := #[]
  createdAt? : Option Timestamp := none
  updatedAt? : Option Timestamp := none
  relationships : Array Relationship := #[]
  leanRefs : Array LeanDeclRef := #[]

end AFTK.KnowledgeBase
```

The exact deriving clauses and JSON instances can be decided during implementation.
Research against Lean's bundled JSON code suggests a likely split:

- small enums and leaf helper structures can likely use `deriving ToJson, FromJson`
- top-level canonical readers should likely use manual object parsing where v1 strictness requires unknown-field rejection

The broader canonical JSON contract is refined in `plans/knowledgebase/serialization.md`.
However, the intended behavior is:

- `NodeId` is stored in JSON as a string
- `Timestamp` is stored in JSON as a string
- enum-like types are stored in JSON as predictable strings
- optional fields may be omitted in JSON
- defaulted collection fields may be omitted in JSON and interpreted as empty

## Field-by-field intent

### `schemaVersion : Nat`

This allows the on-disk JSON format to evolve over time.
The initial version should be `1`.

### `id : NodeId`

This is the canonical node identifier.
It should be present in metadata even if the file layout also implies an identifier, because:

- metadata should be self-describing
- consistency between filesystem layout and metadata should be checkable
- higher layers may want to inspect metadata without reconstructing path-based identity rules

In v1 mutation semantics, this identifier is treated as identity-bearing.
Replacing metadata for an existing node must preserve this ID; changing it is a rename, not an ordinary metadata edit.

### `title : String`

A short human-readable title for the node.
This should usually be required.

### `kind : NodeKind`

A coarse classification of the node’s content.
The initial design keeps this deliberately small.
Additional kinds can be added later if needed.

### `status : NodeStatus`

A lightweight workflow/status field.
This helps distinguish active material from draft, deprecated, or archived content.

### `summary? : Option String`

A short summary or abstract.
This is useful for search results, previews, and listings without reading the full Markdown body.

### `tags : Array String`

Free-form tags for lightweight categorization and filtering.

### `authors : Array String`

Initial provenance support.
This starts simple as a list of names or identifiers.
If richer provenance is needed later, this can be refined in a future schema version.

### `createdAt?` and `updatedAt?`

These are optional timestamp fields stored as ISO-8601 UTC strings.
In v1, the accepted canonical format should be a simple whole-second form such as:

```text
2026-03-07T21:49:18Z
```

The initial implementation should prefer simple string storage plus validation over a more complicated time representation.
Operationally, node creation should auto-populate both timestamps, while body updates, metadata updates, and renames should refresh `updatedAt`.

### `relationships : Array Relationship`

This is the key field that allows the knowledge base to act as a knowledge graph.
Each entry is an outgoing edge from the current node to another node.

The source node is implicit: it is the node whose metadata file is being read.
The target node is explicit in `target : NodeId`.

This means the graph structure emerges naturally from ordinary node metadata files.
We do not need a separate graph store in the first implementation.

### `leanRefs : Array LeanDeclRef`

This records links from the natural-language node to formal Lean declarations.
This is separate from node-to-node relationships because Lean declarations are not themselves knowledge-base nodes.

## Relationship design

The initial design treats relationships as directed, typed edges.
For a node `A`, a relationship entry inside `A`’s metadata means:

- source = `A`
- target = `relationship.target`
- edge type = `relationship.kind`

This should be enough to support graph-like traversal and queries later.

The initial `RelationshipKind` set is intentionally modest:

- `relatedTo`: generic semantic relation
- `dependsOn`: the current node depends on the target node
- `elaborates`: the current node expands or explains the target node
- `refines`: the current node is a refinement or sharpening of the target node
- `exampleOf`: the current node is an example of the target node
- `hasExample`: the target node is an example associated with the current node
- `seeAlso`: lightweight cross-reference

This set can be extended later.
The initial goal is not to perfectly classify every semantic edge, but to make relationships explicit and machine-readable from the start.

## Required vs optional fields

For the initial design, the most important required fields should be:

- `schemaVersion`
- `id`
- `title`

The remaining fields can initially be optional or defaulted.
That keeps the first usable schema small while still supporting richer metadata when available.

## Initial JSON shape

A representative JSON encoding should look like this:

```json
{
  "schemaVersion": 1,
  "id": "topology.open_cover",
  "title": "Open cover",
  "kind": "definition",
  "status": "draft",
  "summary": "Definition of an open cover of a set.",
  "tags": ["topology", "cover"],
  "authors": ["aftk"],
  "createdAt": "2026-03-07T21:49:18Z",
  "updatedAt": "2026-03-07T21:49:18Z",
  "relationships": [
    {
      "kind": "dependsOn",
      "target": "topology.open_set"
    },
    {
      "kind": "relatedTo",
      "target": "topology.compactness",
      "label": "used in compactness definitions"
    }
  ],
  "leanRefs": [
    {
      "module": "Mathlib/Topology/Basic",
      "declaration": "IsOpen"
    }
  ]
}
```

## Validation expectations

The metadata validator for this schema should eventually check at least the following:

- `schemaVersion` is supported
- `id` is syntactically valid
- `title` is nonempty
- enum fields contain known values
- timestamps, if present, have valid UTC whole-second format such as `2026-03-07T21:49:18Z`
- relationship targets are syntactically valid node identifiers
- relationship targets resolve to existing nodes when full-reference validation is requested
- duplicate or obviously contradictory relationships can be flagged

## Design decisions for v1

The initial metadata design intentionally does **not** include:

- arbitrary top-level JSON blobs
- embedded Markdown content
- separate graph storage outside node metadata
- highly detailed provenance substructures
- a large ontology of relationship kinds

Those can be added later if experience shows they are needed.
For v1, the priority is a small, explicit, implementable Lean type that maps cleanly to JSON.

## Lean 4 reuse findings

Research against `Lean.Data.Json`, `Lean.Elab.Deriving.FromToJson`, `Std.Time`, and bundled Lake helpers suggests the following implementation strategy for metadata.

- `Lean.Data.Json.FromToJson.Basic` already provides `FromJson`/`ToJson` instances for core building blocks such as `String`, `Nat`, `Bool`, `Option`, `Array`, `System.FilePath`, and `Name`.
- `Lean.Elab.Deriving.FromToJson` registers deriving handlers for `ToJson` and `FromJson`, so `NodeKind`, `NodeStatus`, `RelationshipKind`, and other small helper types can likely use `deriving` with minimal boilerplate.
- `Lean.Data.Json.Basic` and `Lean.Data.Json.FromToJson.Basic` provide `Json.getObjVal?`, `Json.getObjValAs?`, `Json.setObjValAs!`, and `Json.opt`, which are enough to hand-write strict object readers and deterministic writers where needed.
- A key caveat from the core code is that derived `FromJson` for structures reads declared fields but does not itself reject extra object fields. Because v1 canonical metadata wants unknown-field rejection, the top-level `NodeMetadata` reader should likely be hand-written rather than relying only on `deriving FromJson`.
- `Lake.Util.JsonObject` is a useful bundled wrapper if we want slightly less boilerplate for manual object decoding while still controlling strictness ourselves.
- `Std.Time.Format` already provides parsers and formatters for Lean-style timestamps, but those parsers are broader than the exact v1 canonical contract. They are a good validation aid, but the final metadata validator should still enforce the exact UTC whole-second form required by this plan.
- If Lean declaration references later become more structured, core Lean already has JSON support for `Name`, so `LeanDeclRef` can evolve without inventing a separate name encoding scheme.

## Open questions for later refinement

- Should `schemaVersion` stay a `Nat`, or should it become a structured version type later?
- Should `authors` remain plain strings, or should they later become structured provenance records?
- Do we want additional relationship kinds in the initial implementation, or should the initial set stay minimal?
- Should relationship records eventually support machine-readable attributes beyond `label` and `note`?
- Should Lean references remain lightweight strings, or eventually become more strongly typed?

## Summary

The initial metadata design centers on a `NodeMetadata` Lean structure backed by JSON on disk.
It includes a canonical node ID, basic descriptive fields, lightweight workflow state, optional timestamps, references into Lean, and directed typed relationships to other knowledge-base nodes.

That design is intended to give the knowledge base a clean, implementable metadata core while also allowing it to function as a knowledge graph when needed.