# Knowledge Base Repair Design

## Status

Component plan and implementation-status document for knowledge-base repair.
This document refines the overall knowledge base plan in `plans/knowledgebase.md` and works together with `plans/knowledgebase/storage.md`, `plans/knowledgebase/node.md`, `plans/knowledgebase/metadata.md`, `plans/knowledgebase/serialization.md`, `plans/knowledgebase/validation.md`, and `plans/knowledgebase/cli.md`.

## Component implementation status

- Overall status: Not implemented beyond placeholder scaffolding
- Implemented in code: Placeholder types only
- Last updated basis: current placeholder `RepairAction` and `RepairPlan` types; no operational repair workflow yet

## Purpose

This document defines the repair model for the knowledge base layer.
It describes how the system should respond when validation finds malformed storage, orphaned files, broken references, or other integrity problems.

The goal is to make repair behavior explicit before implementation begins, especially where automatic mutation could otherwise become unsafe or ambiguous.

Minimal scaffolding types now exist in code.
This file still primarily serves as the design reference for the deferred operational repair implementation.

## Design goals

Repair should:

- be conservative with canonical knowledge-base data
- preserve data whenever possible
- distinguish safe automatic repairs from ambiguous cases
- integrate cleanly with validation
- support previewing repair plans before applying them
- treat derived state as rebuildable and canonical data as precious
- remain suitable for both human use and automation

Lean module and namespace naming for this layer should use `KnowledgeBase` rather than `KB`.
The public CLI should use `lake exe aftk knowledgebase ...`.

## Core repair principles

### 1. Validate first, repair second

Repair should normally be driven by explicit validation findings.
That means repair logic should build on top of the issue model from `plans/knowledgebase/validation.md` rather than inventing a separate notion of system health.

### 2. Never casually destroy canonical data

Canonical Markdown and metadata files are the source of truth.
Repair should not automatically delete canonical data unless the action is clearly safe and explicitly requested.

### 3. Prefer quarantine over deletion

When repair needs to remove or displace suspicious canonical files, it should prefer moving them into a repair quarantine area rather than deleting them outright.

### 4. Do not invent mathematical content automatically

Repair may normalize formatting, rebuild derived state, or resolve certain structural issues.
It should not silently invent substantive Markdown body text or fabricate meaningful metadata content.

### 5. Derived state can be rebuilt freely

Files under `knowledgebase/.aftk/` are not canonical.
Repair may delete or rebuild them much more aggressively than canonical files.

## Relationship to validation

Repair and validation are closely related but distinct:

- **validation** reports problems
- **repair** proposes or applies changes in response to those problems

Not every validation issue should have an automatic repair.
Some issues should remain manual or strategy-dependent.

A natural workflow is:

1. run validation
2. inspect issues
3. construct a repair plan
4. preview the plan
5. apply selected repairs
6. re-run validation

## Repair scopes

Repair should be organized into scopes similar to validation.

### 1. Storage repair

Storage repair addresses root-level and layout-level issues, such as:

- missing internal derived directories
- rebuildable internal state corruption
- manifest formatting normalization when the manifest already parses successfully

### 2. Node repair

Node repair addresses a specific node or node file pair, such as:

- canonical formatting normalization
- certain metadata repairs
- quarantining orphaned files
- strategy-driven resolution of path/ID mismatches

### 3. Whole-knowledge-base repair

This addresses issues that may require scanning multiple nodes, such as:

- broken relationship targets
- duplicate node IDs
- large-scale normalization
- quarantine of unresolved orphan files discovered globally

### 4. Derived-state repair

This covers:

- removing stale indexes
- clearing caches
- rebuilding derived state from canonical storage

This is usually the safest form of repair because it does not alter canonical knowledge.

## Repair safety classes

Repair actions should be classified by safety.
This is important for CLI behavior and automation.

### Automatic-safe

These are repairs that should generally be safe to apply automatically.
Examples:

- creating missing `.aftk/` internal directories
- clearing and rebuilding derived indexes or caches
- rewriting canonical JSON into normalized formatting when it already parses and validates

### Confirm-required

These are repairs that may be reasonable, but should require explicit user confirmation or an apply flag.
Examples:

- moving orphan canonical files into quarantine
- removing or deduplicating clearly redundant relationship edges
- removing broken relationship edges when the user explicitly asks for that strategy

### Manual-or-strategy-required

These are repairs where the system should not guess without direction.
Examples:

- resolving metadata ID vs path ID mismatch
- resolving duplicate node IDs
- recovering from malformed metadata JSON that does not parse
- deciding how to handle missing canonical counterparts for orphan files

## Proposed Lean-level types

```lean
namespace AFTK.KnowledgeBase

inductive RepairSafety
  | automaticSafe
  | confirmRequired
  | manualOrStrategyRequired

inductive RepairScope
  | storage
  | node (id : NodeId)
  | wholeKnowledgeBase
  | derivedState

inductive RepairAction
  | createDir (path : System.FilePath)
  | rewriteFile (path : System.FilePath)
  | moveToQuarantine (from : System.FilePath) (to : System.FilePath)
  | deleteDerivedPath (path : System.FilePath)
  | rebuildDerivedState
  | renameNodeFiles (oldMarkdown : System.FilePath) (oldMetadata : System.FilePath)
                    (newMarkdown : System.FilePath) (newMetadata : System.FilePath)
  | rewriteMetadataId (path : System.FilePath) (newId : NodeId)
  | removeRelationship (nodeId : NodeId) (index : Nat)

structure RepairProposal where
  code : String
  scope : RepairScope
  safety : RepairSafety
  description : String
  actions : Array RepairAction := #[]

structure RepairPlan where
  proposals : Array RepairProposal := #[]

end AFTK.KnowledgeBase
```

This is only a conceptual design.
The exact repair engine can differ, but the core idea should remain: repair is a structured plan of actions with explicit safety classification.

## Quarantine design

When suspicious canonical files need to be displaced, they should be moved into a repair quarantine area rather than deleted.

### Proposed quarantine location

```text
knowledgebase/.aftk/repair/quarantine/
```

A repair run may create a timestamped subdirectory such as:

```text
knowledgebase/.aftk/repair/quarantine/2026-03-07T22-30-00Z/
```

Inside that directory, repaired-away files can be stored in a path-preserving form.

### Why quarantine matters

Quarantine is important because some repair actions are structurally sensible but semantically uncertain.
Moving files to quarantine preserves data for later inspection while still allowing the canonical tree to be cleaned up.

## Repairable issue categories

### Storage and derived-state issues

These are usually the easiest to repair.
Examples:

- missing `.aftk/` directory
- missing `.aftk/index/`, `.aftk/cache/`, or `.aftk/tmp/`
- stale or corrupt derived state
- manifest or metadata files that are semantically valid but not canonically formatted

Typical repair approach:

- create missing internal directories
- delete/rebuild derived state
- rewrite canonical JSON into normalized formatting when safe

### Orphan canonical files

Examples:

- `.md` file exists without `.json`
- `.json` file exists without `.md`

These are dangerous because the correct resolution is often ambiguous.
The default repair behavior should be conservative:

- do **not** delete automatically
- allow moving the orphan file to quarantine
- allow future strategy-driven commands if we later add richer recovery modes

### Metadata/path ID mismatch

Example:

- file path implies `topology.open_cover`
- metadata says `topology.open_cover_old`

This is a classic ambiguous repair.
The system should not silently choose one identity over the other.
Instead, repair should require an explicit strategy.

Reasonable strategies might include:

- **adopt-path-id**: rewrite metadata ID to match the canonical path
- **adopt-metadata-id**: rename files to match the metadata ID

The system should make the ambiguity explicit.

### Duplicate node IDs

If two canonical node pairs claim the same `NodeId`, repair should normally be manual or strategy-driven.
This is not a case where the system should guess which node is authoritative.

Possible future workflows could involve quarantining one copy, but that should not be the silent default.

### Broken relationship targets

Examples:

- a relationship points to a nonexistent node

Default repair behavior should be conservative.
Possible strategies include:

- leave the issue as validation-only
- remove the broken relationship when explicitly requested
- quarantine or rewrite affected metadata only with confirmation

The system should not automatically guess a replacement target.

### Duplicate or redundant relationships

If two identical outgoing edges appear in one node’s metadata, this may be safely repairable in some cases.
A reasonable repair option is:

- remove exact duplicates with confirmation

This is safer than trying to reason about deeper semantic contradictions.

## Repair policies by class

### Safe automatic repair candidates for v1

The following should be considered good candidates for early automatic repair support:

- create missing internal `.aftk/` subdirectories
- clear or rebuild derived indexes/caches
- rewrite manifest JSON into canonical formatting when it parses successfully
- rewrite metadata JSON into canonical formatting when it parses successfully and validation passes

### Confirmed repair candidates for v1

These are plausible early repair features, but should require explicit apply/confirmation:

- move orphan Markdown or metadata files to quarantine
- remove exact duplicate relationship entries
- remove broken relationship entries when asked explicitly

### Manual/strategy-dependent cases for v1

These should not be automatic in the first implementation:

- choose between path ID and metadata ID during mismatch repair
- resolve duplicate node IDs
- synthesize missing metadata or body content
- recover from unparseable metadata in a semantics-preserving way

## CLI alignment

The CLI plan already leaves room for a deferred `repair` command family.
This document refines what that family should eventually mean.

### Proposed command family

```text
lake exe aftk knowledgebase repair ...
```

### Candidate commands

#### `repair plan`

Construct a repair plan without applying changes.

```text
lake exe aftk knowledgebase repair plan
lake exe aftk knowledgebase repair plan --root ./knowledgebase
```

This should likely run validation internally and produce a structured repair plan.

#### `repair storage`

Repair storage-level and derived-state issues.

```text
lake exe aftk knowledgebase repair storage --apply
```

#### `repair node <id>`

Repair a single node where possible.

```text
lake exe aftk knowledgebase repair node topology.open_cover --apply
```

#### `repair all`

Apply or preview broader repair logic across the whole knowledge base.

```text
lake exe aftk knowledgebase repair all
lake exe aftk knowledgebase repair all --apply
```

### Important flags

The repair CLI should likely support flags such as:

- `--apply` — actually perform repairs
- `--dry-run` — explicit preview mode
- `--quarantine` — allow or require quarantine-backed repair behavior
- `--rebuild-derived` — rebuild `.aftk` state
- strategy flags for ambiguous repairs, such as adopting path ID versus metadata ID

## Output model

### Text output

Text output should make these distinctions clear:

- detected issues
- proposed actions
- safety class of each proposal
- whether changes were actually applied
- where quarantined files were moved

### JSON output

JSON output should expose structured repair plans and results.
A repair result should ideally include:

- scope
- proposal list
- applied actions
- unapplied proposals
- quarantine paths if used
- warnings or manual-follow-up notes

## Interaction with serialization

Repair and serialization interact closely.
Some repairs are really normalization actions:

- canonical pretty-print rewrite
- field-order normalization
- omission of absent/default fields according to canonical writer policy

Those repairs are only safe when the file already parses into a valid semantic object.
Repair should not use formatting normalization to conceal invalid semantics.

## Interaction with validation severities

Repair should not be keyed only off the presence of an issue.
It should also care about severity and ambiguity.
For example:

- warnings may or may not need repair
- some errors may still be manual-only
- some informational findings may support safe normalization

That means validation reports help drive repair, but do not mechanically determine it.

## Recommended first implementation slice

Repair is not part of the first essential implementation slice for the knowledge base.
However, when repair work begins, the first repairs should likely be:

1. rebuild/clear derived state under `.aftk/`
2. create missing internal directories
3. normalize manifest formatting
4. normalize metadata formatting for already-valid nodes
5. quarantine orphan canonical files with confirmation

This gives useful operational value without forcing the implementation to solve difficult semantic ambiguities too early.

## Design decisions for v1

The initial repair design intentionally does **not** require:

- automatic invention of missing mathematical content
- automatic resolution of duplicate canonical nodes
- automatic guessing of intended node identity in ambiguous mismatch cases
- semantic repair of mathematical meaning
- deep graph repair beyond straightforward broken-edge cleanup when explicitly requested

Those may be revisited later, but v1 repair should remain conservative and data-preserving.

## Lean 4 reuse findings

The existing IO and bundled Lake utilities already support most of the mechanics a conservative repair engine needs.

- `IO.FS.withTempFile` and `rename` support safe rewrite-and-replace flows for normalized manifest or metadata files.
- `IO.FS.createTempDir` and `IO.FS.withTempDir` are good fits for staging rebuilt derived state or quarantine preparation.
- `IO.FS.removeFile` and `IO.FS.removeDirAll` support aggressive cleanup of derived state under `.aftk/`.
- `System.FilePath.symlinkMetadata` is especially relevant for repair because it allows the tool to inspect suspicious entries without accidentally traversing or mutating through symlinks.
- `IO.FS.Metadata.modified` and `byteSize` are available if quarantine manifests later want to record lightweight forensic context.
- `Lake.Util.Log`, `Lake.Util.MainM`, and `Lake.Util.Cli` are plausible reusable building blocks for repair-plan, dry-run, and apply commands if importing bundled Lake modules is acceptable.
- Lake's manifest save/load pattern is also a good reference for repair actions that normalize already-parseable JSON and then write it back deterministically.

## Open questions for later refinement

- Should repair plan construction always run validation internally, or may it also accept existing validation reports?
- How much of relationship cleanup should be available in the first repair implementation?
- Should quarantine contents be automatically garbage-collected later, or always kept until manual deletion?
- Should there be separate commands for normalization versus semantic repair?
- How should ambiguous repair strategies be encoded in the CLI without becoming too complicated?

## Summary

The knowledge-base repair system should be conservative, validation-driven, and explicitly structured around repair plans.
It should preserve canonical data, prefer quarantine over deletion, freely rebuild derived state, and require strategy selection for ambiguous cases.

The eventual public CLI family should look like:

- `lake exe aftk knowledgebase repair plan`
- `lake exe aftk knowledgebase repair storage`
- `lake exe aftk knowledgebase repair node <id>`
- `lake exe aftk knowledgebase repair all`

That gives the knowledge base a practical integrity-recovery story without making unsafe guesses about canonical content.