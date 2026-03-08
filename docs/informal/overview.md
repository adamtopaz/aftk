# Informal layer overview

The informal layer is the Lean-facing bridge between the knowledge base and Lean declarations.
It is implemented in `AFTK.Informal` and exposed both as library code and as a CLI.

Public entrypoints:

- library: `import AFTK.Informal`
- CLI: `lake exe aftk informal ...`

For a component-by-component guide with direct code pointers, see `docs/informal/library.md`.

## What the layer does today

The current implementation provides:

- bracketed `informal[...]` term syntax
- knowledge-base-backed reference validation and resolution
- an explicit unsound placeholder primitive for gradual formalization
- declaration-level tracking of successful informal references
- reverse reference → declarations queries
- derived declaration and reference dependency views
- compact and rich presentation renderers
- an informal CLI for querying tracking state and rendering node presentation

## What it does not do

The current implementation deliberately does **not**:

- create a second `informal/` prose store
- mutate knowledge-base content
- infer formal Lean types from prose metadata or body text
- expose public per-site tracking APIs
- persist dependency graphs as canonical data

## Core architectural rule

The most important rule is:

> `informal[...]` resolves through the knowledge base.

That means the informal layer depends on `AFTK.KnowledgeBase` for node identity and storage lookup.
It does not own canonical prose.

## Syntax and elaboration model

### Surface syntax

The implemented syntax is bracketed only:

```lean
informal[group.basic.definition]
```

Bare `informal` is not supported.

The bracket payload is parsed as identifier-shaped Lean syntax and then validated semantically against `KnowledgeBase.NodeId` rules.
So the real semantic contract is still the knowledge-base node-id grammar.

### Where it may be used

The elaborator requires a real declaration context.
It rejects pseudo-command contexts such as:

- `_check`
- `_reduce`
- `_synth_cmd`
- `_eval`-like generated contexts

In practice, the supported use sites are declaration values and proofs.

### How elaboration works

At a high level, elaboration does this:

1. recover the raw node-id text from `informal[...]`
2. validate it as an `InformalReference`
3. resolve it through the knowledge base
4. elaborate any explicit arguments normally
5. determine the placeholder result type from the expected type or a fresh metavariable
6. build a placeholder expression using `AFTK.Informal.Informal`
7. generate a site-unique tag from source-location information
8. attach a compact presentation summary to the info tree
9. record the declaration/reference occurrence in the persistent tracking extension

### Placeholder primitive

The core primitive is the explicit axiom:

```lean
axiom Informal.{u} (tag : Lean.Name) (α : Sort u) : α
```

This is intentionally unsound and is documented as such.
Its purpose is gradual formalization: it lets a declaration typecheck while preserving a distinct tag per occurrence.

## Root resolution

### Default behavior

Informal reference resolution defaults to the same root policy as the knowledge-base layer:

```text
knowledgebase/
```

relative to the current working directory.

### Lean-side override

Lean code can override the root with the registered option:

```lean
set_option aftk.informal.root "tests/informal/knowledgebase-fixtures/basic-valid"
```

This is how the fixture modules point elaboration at test knowledge bases.

### CLI-side override

The informal CLI uses `--root <path>` for commands that need direct knowledge-base access, especially `present`.

## Tracking model

### Public tracking semantics

Tracking is declaration-level and deduplicated.
If one declaration mentions the same node id multiple times, the public tracking view still stores only one reference for that declaration.

Example from the fixtures:

- `repeatedRef` uses `informal[group.basic.definition]` twice
- the tracked declaration row still contains one reference entry for `group.basic.definition`

### Persistent state

Tracking is implemented with a `SimplePersistentEnvExtension`.
The persisted information is just:

- declaration name
- referenced node id

The layer does **not** persist resolved node bodies, metadata snapshots, or dependency indexes.

### Reverse lookup

The reverse view from reference to declarations is derived on demand from the persistent declaration→reference state.

## Dependency views

The layer exposes two derived dependency projections.

### Declaration dependencies

A declaration dependency row records which other tracked declarations are transitively reachable through Lean's used-constant information.
The traversal continues through untracked declarations and filters down to tracked ones at the public boundary.

### Reference dependencies

A reference dependency row projects the declaration dependency graph through tracked declaration→reference associations.
This is still a declaration-derived view, not a knowledge-base graph.

### Leaves

The layer also exposes leaves for both projections:

- tracked declarations with no tracked dependencies
- tracked references with no projected dependencies

## Presentation

The presentation layer has two output shapes.

### Compact summary

Used mainly at elaboration time and for lightweight hover-like rendering.
Current compact fields are:

- reference id
- title
- kind
- status
- summary

### Rich presentation

Used by explicit CLI rendering and by the server's richer hover integration.
Current rich payload may include:

- sorted tags
- sorted authors
- sorted relationship lines
- sorted Lean-ref lines
- body rendering in `none`, `preview`, or `full` mode

The default preview policy is currently conservative:

- up to 6 lines
- up to 250 characters
- explicit `[truncated]` marker when clipping occurs

## CLI surface

The informal CLI is query-oriented.
Current commands are:

- `status`
- `decls`
- `decl <Decl.Name>`
- `refs`
- `ref <NodeId>`
- `deps`
- `present <NodeId>`

Important rule:

- all environment-backed commands require at least one `--module <Module.Name>`
- `present` is knowledge-base-backed and does not require `--module`

## Relationship to the server layer

The server/file-worker layer reuses this layer in two different ways:

1. ordinary Lean elaboration already attaches compact info-tree summaries for `informal[...]`
2. the file worker adds a richer hover path for recognized `informal[...]` syntax sites by re-resolving the node and rendering preview text

So the informal layer provides both the semantic bridge and the reusable presentation machinery.

## A short example

Fixture code:

```lean
set_option aftk.informal.root "tests/informal/knowledgebase-fixtures/basic-valid"

namespace Demo

noncomputable section

def placeholder : Nat :=
  informal[group.basic.definition]

end
```

What this gives you today:

- the term elaborates as a typed placeholder
- the declaration is tracked as referencing `group.basic.definition`
- the informal CLI can report that declaration/reference association
- the server can show rich preview text when hovering that site in a file worker session

## Where to read next

- `docs/informal/library.md`
- `docs/informal/cli.md`
- `docs/informal/testing.md`
