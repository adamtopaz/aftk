# PRD and Implementation Plan: Repository-Local Knowledge Base Infrastructure (Lean CLI)

## Status

Planning only. This document specifies the intended product behavior and implementation plan.
No code changes are made by this document itself.

This document replaces the old `plan.md`, which planned Informalize metadata sidecars and CLI metadata management. That work is now already reflected in the repository (`Informalize/Metadata.lean`, `Informalize/Cli.lean`, tests, and docs), so the next planning target is the knowledge base layer.

---

## 1. Current project state

The current repository already has two substantial foundations:

### 1.1 Informalize blueprint layer exists now

Implemented today:

- `informal[...]` placeholders in Lean,
- required markdown sidecars under `informal/.../*.md`,
- optional JSON metadata sidecars under `informal/.../*.json`,
- a Lean CLI (`lake exe informalize ...`) for:
  - declaration and location tracking,
  - declaration-level and location-level dependency queries,
  - metadata inspection and mutation,
- tests for metadata parsing, hover formatting, and CLI behavior.

So the scaffold/blueprint layer is no longer the missing piece.

### 1.2 AFTK Lean-local execution layer exists now

Implemented today:

- `aftk_file_worker`,
- `aftk_server`,
- hover/goal/tactic exploration support in Lean.

So the repository already supports the local formalization inner loop.

### 1.3 The major missing layer is the knowledge base

The docs describe a broader workflow that still does **not** exist yet in code:

- source registry,
- faithful source-packet ingestion/storage,
- knowledge store entries,
- knowledge query/writeback APIs,
- provenance tracking across those layers.

That gap is explicit in:

- `docs/workflow.md`,
- `docs/components.md`,
- `docs/future/autoformalization-tools.md`.

### 1.4 Important implication for this plan

We should **not** redesign Informalize metadata or the existing `informalize` CLI as the main vehicle for the knowledge base.

Instead, we should build a **new knowledge-base-focused CLI in Lean**, while keeping it consistent with the style and patterns already established by `Informalize.Cli`.

---

## 2. Problem statement

Right now, the repository can:

- represent scaffold nodes in Lean,
- attach markdown and metadata to those nodes,
- inspect declaration/location dependencies,
- explore local tactic branches.

But it cannot yet do the source-first memory management that the workflow requires.

In particular, there is currently no repository-local system for:

1. registering sources with stable ids,
2. storing faithful, queryable source packets,
3. creating reusable knowledge entries derived from those packets,
4. distinguishing source-backed knowledge from agent-derived knowledge,
5. querying that knowledge from a stable machine-facing interface,
6. writing new knowledge back into the project over time,
7. validating that provenance remains explicit and inspectable.

This means that:

- `knowledgeRefs` in Informalize metadata are currently just string pointers with no in-repo authority behind them,
- agents must improvise their own source/knowledge memory outside the project,
- the documented workflow cannot yet be executed end-to-end inside the repo.

---

## 3. Product vision

We want a **repository-local, source-first knowledge base infrastructure** whose primary interaction surface is a **Lean CLI**.

The first implementation should make the repository able to persist and query:

- source records,
- source packets,
- knowledge entries,
- provenance links among them,
- links from knowledge entries to scaffold nodes.

The knowledge base should be:

- machine-readable,
- agent-friendly,
- human-inspectable in git,
- incrementally updateable,
- explicit about provenance,
- explicit about source-backed vs derived content.

The CLI should be the supported interaction surface for agents, just as the Informalize CLI is the supported interaction surface for scaffold metadata.

---

## 4. Goals

## 4.1 Functional goals

1. Register raw sources with stable ids and metadata.
2. Store faithful source packets derived from those sources.
3. Store reusable knowledge entries derived from sources, packets, or later workflow steps.
4. Support both source-backed entries and agent-derived entries.
5. Support explicit provenance and links among records.
6. Support incremental writeback at any point in the workflow.
7. Provide query operations through a Lean CLI.
8. Provide machine-readable `--json` output from the beginning.
9. Keep the storage local to the repository and inspectable in git.
10. Integrate cleanly with existing Informalize location ids and `knowledgeRefs` conventions.

## 4.2 Workflow goals

1. Make the knowledge base available at any point in the workflow, as required by `docs/workflow.md`.
2. Preserve source traceability throughout the project.
3. Let agents query definitions, theorems, notation, examples, proof sketches, and outcomes without re-reading raw sources every time.
4. Let agents record derived notes, failures, and formalization outcomes back into the project.
5. Create a foundation for later readiness assessment, frontier prioritization, and orchestration.

## 4.3 Implementation goals

1. Implement the primary interface in Lean.
2. Reuse patterns from the existing Informalize CLI where sensible:
   - manual argument parsing,
   - plain text + JSON outputs,
   - explicit validation,
   - canonical file writes.
3. Keep the initial backend file-backed and repository-local.
4. Keep the initial query engine simple and deterministic.

---

## 5. Non-goals for the first implementation

The first knowledge-base implementation should **not** attempt to solve the entire autoformalization framework.

Out of scope for v1:

1. PDF parsing, OCR, or rich document conversion pipelines.
2. LLM-driven automatic knowledge extraction.
3. Embedding search or vector databases.
4. A long-running knowledge-base server process.
5. A distributed or remote multi-user knowledge service.
6. Full workflow orchestration, frontier computation, or readiness classification.
7. Automatic scaffold generation.
8. Automatic synchronization of Informalize `knowledgeRefs` with the new store in both directions.
9. Rich ranking/relevance modeling beyond deterministic filtering and simple text search.
10. Replacing Informalize CLI or AFTK hub surfaces.

The v1 goal is infrastructure: persistent storage, validation, query, and writeback.

---

## 6. Knowledge-base requirements extracted from current docs

This section consolidates the requirements already present in the project documentation.

## 6.1 Source-first requirement

Per `docs/workflow.md`, the system must remain source-first:

- scaffold nodes and formalization decisions should be traceable to source material or explicit derived reasoning,
- source provenance must not be lost during ingestion or knowledge extraction.

## 6.2 Faithful-ingestion requirement

Source packets must preserve:

- normalized text,
- structural anchors,
- chunk boundaries,
- provenance back to the raw source,
- explicit representation of incomplete/low-quality inputs rather than silently hiding that fact.

## 6.3 Knowledge-store requirement

Knowledge entries must support at least:

- stable ids,
- type/classification,
- provenance,
- links to related entries,
- explicit distinction between source-backed and derived.

## 6.4 Query/writeback requirement

The docs explicitly require that the agent can:

- query the knowledge base at any time,
- add new material to it at any time.

So the CLI must support both read and mutation flows from the start.

## 6.5 Provenance discipline requirement

The knowledge base must never blur together:

- source-backed facts,
- derived notes or hypotheses,
- later formalization outcomes.

This must be a schema-level invariant, not just a social convention.

## 6.6 Incrementality requirement

The store must support repeated updates without full rebuilds.

That means:

- add one source,
- ingest one packet,
- add one knowledge entry,
- mutate one entry,
- query immediately.

## 6.7 Agent-readable requirement

Outputs should be designed for agents, not only humans.

Therefore:

- `--json` output is mandatory for the main read/query commands,
- ids and schemas should be stable,
- errors should be explicit and actionable.

---

## 7. Key product decisions

## 7.1 Build a new AFTK CLI instead of extending `informalize`

The knowledge base is broader than blueprint metadata.

Planned decision:

- keep `lake exe informalize ...` focused on scaffold state,
- add a new Lean CLI for knowledge-base operations.

Recommended executable:

- `lake exe aftk ...`

Recommended initial command namespaces:

- `source ...`
- `packet ...`
- `kb ...`
- optionally `store ...` or `index ...`

Rationale:

- avoids overloading the blueprint CLI,
- matches the repository architecture more naturally,
- leaves room for future orchestration commands under the same executable.

## 7.2 Use a repository-local file-backed backend for v1

Planned decision:

- store records in the repository as JSON and markdown sidecars,
- do not depend on SQLite or a long-running service in v1.

Rationale:

- easier to implement in Lean now,
- inspectable in git,
- aligns with the project’s existing sidecar/document style,
- good enough for MVP-scale stores.

## 7.3 Use typed stable ids with dotted-string encoding

Planned id families:

- `src.*` for sources,
- `pkt.*` for source packets,
- `kb.*` for knowledge entries.

Examples:

- `src.paper.smith2024`
- `pkt.paper.smith2024.thm_2_3`
- `kb.group.definition`

Rationale:

- stable and readable,
- easy to render in JSON,
- easy to map to filesystem paths,
- consistent with existing `knowledgeRefs` examples like `kb.fixture.foo_bar`.

## 7.4 Long-form text should live in sidecars, not inside giant JSON blobs

Planned decision:

- structured metadata in JSON,
- larger textual bodies in adjacent markdown files when needed.

Rationale:

- better diffs,
- better human inspection,
- consistent with Informalize’s successful `.json` + `.md` pattern.

## 7.5 Source-backed vs derived must be an explicit field

Planned decision:

- store this distinction directly in each knowledge entry.

Do **not** infer it heuristically from whether citations exist.

Rationale:

- derived notes can still cite sources,
- source-backed entries may still include interpretation notes,
- explicit classification is more reliable for agents.

## 7.6 Start with scan-based queries; optimize later only if needed

Planned decision:

- v1 query execution can scan canonical on-disk records,
- persistent secondary indexes are optional follow-on work.

Rationale:

- simplifies correctness,
- avoids premature backend complexity,
- acceptable for the likely initial repository scale.

## 7.7 JSON output is part of the MVP, not a follow-up

All important read/query commands should support:

- plain text output for humans,
- `--json` output for agents.

This is especially important for:

- `source show`
- `source list`
- `packet show`
- `packet list`
- `kb show`
- `kb list`
- `kb query`
- validation commands.

---

## 8. Proposed repository layout

Recommended root directory:

- `aftk-data/`

Recommended layout:

```text
aftk-data/
  store.json
  sources/
    ...source record json files...
  packets/
    ...packet json files...
    ...packet markdown bodies...
  knowledge/
    ...knowledge entry json files...
    ...knowledge entry markdown bodies...
```

Concrete layout:

```text
aftk-data/
  store.json
  sources/
    paper/
      smith2024.json              # src.paper.smith2024
  packets/
    paper/
      smith2024/
        thm_2_3.json              # pkt.paper.smith2024.thm_2_3
        thm_2_3.md
  knowledge/
    group/
      definition.json             # kb.group.definition
      definition.md
```

## 8.1 `store.json`

Purpose:

- mark the repository as containing an AFTK knowledge store,
- hold store-level schema/version metadata,
- possibly hold small future configuration settings.

Minimal planned contents:

```json
{
  "schemaVersion": 1
}
```

## 8.2 Path-mapping rule

For dotted ids, the first component is the family prefix and the remaining components map to directories + final filename.

Examples:

- `src.paper.smith2024` -> `aftk-data/sources/paper/smith2024.json`
- `pkt.paper.smith2024.thm_2_3` ->
  - `aftk-data/packets/paper/smith2024/thm_2_3.json`
  - `aftk-data/packets/paper/smith2024/thm_2_3.md`
- `kb.group.definition` ->
  - `aftk-data/knowledge/group/definition.json`
  - `aftk-data/knowledge/group/definition.md`

This path logic should be centralized in a shared Lean module.

## 8.3 Store discovery

Planned behavior:

- CLI resolves the nearest ancestor containing `aftk-data/store.json`,
- `--store <path>` can override discovery.

Rationale:

- agent-friendly inside nested working directories,
- explicit override when operating on a non-default store.

---

## 9. Proposed data model

## 9.1 ID types

Add typed wrappers rather than using raw strings everywhere.

Planned types:

- `AFTK.SourceId`
- `AFTK.PacketId`
- `AFTK.KnowledgeId`

Planned encoding:

- opaque dotted strings in JSON.

Validation should require:

- a correct family prefix (`src`, `pkt`, `kb`),
- at least one component after the prefix,
- non-empty components,
- a conservative allowed-character set per component.

Unlike Informalize location ids, these ids should **not** be constrained to `Lean.Name` syntax.

## 9.2 Source model

### `AFTK.SourceKind`

Planned values:

- `paper`
- `book`
- `notes`
- `prior_formalization`
- `web`
- `local_file`
- `other`

### `AFTK.SourceLocator`

Minimal initial representation should support:

- local path,
- URI,
- freeform locator note.

### `AFTK.SourceRecord`

Planned fields:

- `id : SourceId`
- `kind : SourceKind`
- `title : String`
- `authors : Array String := #[]`
- `locator : SourceLocator`
- `version? : Option String := none`
- `contentHash? : Option String := none`
- `license? : Option String := none`
- `tags : Array String := #[]`
- `note? : Option String := none`

Purpose:

- register raw sources with stable ids and enough metadata for later provenance.

## 9.3 Source-packet model

### `AFTK.PacketAnchor`

Planned fields:

- `id : String`
- `kind? : Option String := none`
- `label? : Option String := none`
- `locator? : Option String := none`

Examples of anchor kinds:

- `section`
- `subsection`
- `definition`
- `theorem`
- `example`
- `equation`
- `page_range`
- `chunk`

### `AFTK.PacketProvenance`

Minimal planned fields:

- `source : SourceId`
- `locator? : Option String := none`
- `anchors : Array String := #[]`
- `note? : Option String := none`

### `AFTK.SourcePacket`

Planned fields:

- `id : PacketId`
- `source : SourceId`
- `title : String`
- `summary? : Option String := none`
- `anchors : Array PacketAnchor := #[]`
- `provenance : Array PacketProvenance := #[]`
- `tags : Array String := #[]`

Long-form packet content lives in the packet markdown body sidecar.

Purpose:

- persist a faithful, agent-readable chunk or normalized unit derived from a source.

## 9.4 Knowledge model

### `AFTK.KnowledgeBasis`

Planned values:

- `source_backed`
- `derived`

### `AFTK.KnowledgeKind`

Planned values:

- `definition`
- `theorem_statement`
- `proof_sketch`
- `notation`
- `example`
- `counterexample`
- `dependency_hint`
- `plan_note`
- `formalization_outcome`
- `other`

### `AFTK.ProvenanceRef`

This is the main provenance/citation primitive for knowledge entries.

Planned fields:

- `targetId : String`
- `targetKind : String`  
  planned values initially: `source`, `packet`, `knowledge`, `scaffold`
- `anchors : Array String := #[]`
- `locator? : Option String := none`
- `note? : Option String := none`
- `quote? : Option String := none`

Validation should ensure that `targetId` matches the declared family where possible.

### `AFTK.KnowledgeLink`

Planned fields:

- `relation : String`
- `target : KnowledgeId`

Typical relation values:

- `supports`
- `related`
- `uses_notation`
- `specializes`
- `generalizes`
- `example_for`
- `counterexample_for`
- `outcome_for`

### `AFTK.KnowledgeEntry`

Planned fields:

- `id : KnowledgeId`
- `kind : KnowledgeKind`
- `basis : KnowledgeBasis`
- `title : String`
- `summary? : Option String := none`
- `packetRefs : Array PacketId := #[]`
- `sourceRefs : Array SourceId := #[]`
- `scaffoldRefs : Array Informalize.LocationId := #[]`
- `provenance : Array ProvenanceRef := #[]`
- `links : Array KnowledgeLink := #[]`
- `tags : Array String := #[]`

Long-form knowledge content lives in the knowledge-entry markdown body sidecar.

Purpose:

- represent reusable mathematical/project knowledge retrievable during the workflow.

## 9.5 Validation invariants

At minimum:

### Sources

- source ids are unique,
- `title` is non-empty,
- locator is well-formed,
- tags/authors are normalized.

### Packets

- packet ids are unique,
- referenced source exists,
- title is non-empty,
- packet provenance points back to the owning source or another explicitly allowed source,
- anchor ids are unique within a packet.

### Knowledge entries

- knowledge ids are unique,
- `title` is non-empty,
- referenced sources/packets exist,
- referenced scaffold ids parse as valid Informalize locations,
- link targets exist,
- provenance references are well-formed,
- if `basis = source_backed`, at least one source- or packet-level provenance ref exists.

---

## 10. CLI surface

## 10.1 Top-level shape

Recommended executable:

```bash
lake exe aftk <namespace> <command> [options]
```

Namespaces for v1:

- `store`
- `source`
- `packet`
- `kb`

## 10.2 Store commands

### `store init`

Initialize `aftk-data/` in the current directory.

Example:

```bash
lake exe aftk store init
```

### `store validate`

Validate the whole store.

Example:

```bash
lake exe aftk store validate
```

### `store stats`

Show counts of sources, packets, and knowledge entries.

Example:

```bash
lake exe aftk store stats --json
```

## 10.3 Source commands

### Read operations

- `source list`
- `source show --id <SourceId>`
- `source validate --id <SourceId>`

### Write operations

- `source register --id <SourceId> --kind <Kind> --title <Title> (--path <Path> | --uri <Uri> | --locator-note <Text>) [options]`
- `source update --id <SourceId> [field options or --from-json <File>]`
- `source remove --id <SourceId>`

Useful repeatable options:

- `--author <Author>`
- `--tag <Tag>`

## 10.4 Packet commands

### Read operations

- `packet list [--source <SourceId>]`
- `packet show --id <PacketId>`
- `packet validate --id <PacketId>`

### Write operations

- `packet ingest --id <PacketId> --source <SourceId> --title <Title> --body-file <Path> [options]`
- `packet update --id <PacketId> [field options or --from-json <File>]`
- `packet remove --id <PacketId>`

Useful repeatable options:

- `--anchor <AnchorId>`
- `--anchor-kind <Kind>`
- `--anchor-label <Label>`
- `--anchor-locator <Locator>`
- `--prov-anchor <Anchor>`
- `--prov-locator <Locator>`
- `--tag <Tag>`

For complex packet metadata, `--from-json <File>` should be supported.

## 10.5 Knowledge-entry commands

### Read operations

- `kb list`
- `kb show --id <KnowledgeId>`
- `kb validate --id <KnowledgeId>`
- `kb query [filters...]`

### Write operations

- `kb create --id <KnowledgeId> --kind <Kind> --basis <Basis> --title <Title> --body-file <Path> [options]`
- `kb update --id <KnowledgeId> [field options or --from-json <File>]`
- `kb remove --id <KnowledgeId>`
- `kb add-link --id <KnowledgeId> --relation <Relation> --target <KnowledgeId>`
- `kb remove-link --id <KnowledgeId> --relation <Relation> --target <KnowledgeId>`
- `kb add-tag --id <KnowledgeId> --tag <Tag>`
- `kb remove-tag --id <KnowledgeId> --tag <Tag>`
- `kb add-scaffold-ref --id <KnowledgeId> --location <Informalize.Location>`
- `kb remove-scaffold-ref --id <KnowledgeId> --location <Informalize.Location>`

Useful repeatable options for `kb create` / `kb update`:

- `--packet <PacketId>`
- `--source <SourceId>`
- `--location <Informalize.Location>`
- `--tag <Tag>`
- `--prov-target <Id>`
- `--prov-kind <source|packet|knowledge|scaffold>`
- `--prov-anchor <Anchor>`
- `--prov-locator <Locator>`
- `--prov-note <Note>`
- `--prov-quote <Quote>`

## 10.6 Query semantics

The initial `kb query` should support deterministic filters for:

- `--id-prefix <Prefix>`
- `--kind <KnowledgeKind>`
- `--basis <source_backed|derived>`
- `--tag <Tag>`
- `--source <SourceId>`
- `--packet <PacketId>`
- `--location <Informalize.Location>`
- `--related-to <KnowledgeId>`
- `--text <Substring>`
- `--limit <Nat>`

Initial text search can be case-insensitive substring matching over:

- id,
- title,
- summary,
- markdown body.

Results should be sorted deterministically, with no opaque ranking requirement in v1.

## 10.7 Output modes

All major commands should support:

- plain text default,
- `--json` structured output.

For mutation commands, JSON output should include:

- action,
- id,
- paths written,
- resulting record summary.

---

## 11. Example user flows

## 11.1 Register a source and ingest a packet

```bash
lake exe aftk store init
lake exe aftk source register \
  --id src.paper.smith2024 \
  --kind paper \
  --title "Smith 2024" \
  --path sources/smith2024.txt

lake exe aftk packet ingest \
  --id pkt.paper.smith2024.thm_2_3 \
  --source src.paper.smith2024 \
  --title "Theorem 2.3 excerpt" \
  --body-file tmp/thm_2_3.md \
  --anchor thm-2-3 \
  --anchor-kind theorem \
  --prov-locator "Theorem 2.3"
```

## 11.2 Create a source-backed knowledge entry

```bash
lake exe aftk kb create \
  --id kb.group.definition \
  --kind definition \
  --basis source_backed \
  --title "Definition of group" \
  --body-file tmp/group-definition.md \
  --packet pkt.paper.smith2024.thm_2_3 \
  --source src.paper.smith2024 \
  --location Algebra.Group.definition \
  --tag algebra
```

## 11.3 Query knowledge for a scaffold node

```bash
lake exe aftk kb query --location Algebra.Group.definition --json
```

## 11.4 Write back a derived project note

```bash
lake exe aftk kb create \
  --id kb.plan.group.definition.translation_note \
  --kind plan_note \
  --basis derived \
  --title "Translation note for group definition" \
  --body-file tmp/translation-note.md \
  --location Algebra.Group.definition \
  --packet pkt.paper.smith2024.thm_2_3
```

---

## 12. Error model

## 12.1 Store-level errors

### Missing store root

If no `aftk-data/store.json` is found and no `--store` path is provided, commands should fail clearly.

Suggested style:

- `no AFTK knowledge store found (expected aftk-data/store.json in this directory or an ancestor)`

### Store not initialized

Mutation commands should not silently initialize the store.

Suggested policy:

- require explicit `store init`.

## 12.2 Validation errors

Examples:

- invalid id family prefix,
- duplicate anchor id,
- source-backed knowledge entry with no source/packet provenance,
- packet references unknown source,
- knowledge link target missing,
- malformed JSON record.

Errors should mention:

- the path or id involved,
- the field or relation that failed,
- the expected correction when possible.

## 12.3 Removal errors

Planned policy for v1:

- default behavior should reject removal of records that are still referenced,
- optional future `--force` can be considered later.

This is safer for provenance integrity.

---

## 13. Architecture and module plan

## 13.1 New executable

Add:

- `AFTKCli.lean`
- `lean_exe aftk` in `lakefile.lean`

## 13.2 Proposed module structure

Possible Lean modules:

- `AFTK/Cli.lean`
- `AFTK/Store.lean`
- `AFTK/StoreDiscovery.lean`
- `AFTK/Id.lean`
- `AFTK/Source.lean`
- `AFTK/Packet.lean`
- `AFTK/Knowledge.lean`
- `AFTK/Provenance.lean`
- `AFTK/Query.lean`
- `AFTK/Filesystem.lean`

Responsibilities:

### `AFTK/Id.lean`

- typed ids,
- dotted-string validation,
- path derivation helpers.

### `AFTK/Filesystem.lean`

- canonical JSON write helpers,
- atomic write/rename helpers,
- directory creation,
- safe deletion helpers.

### `AFTK/StoreDiscovery.lean`

- nearest-store lookup,
- explicit `--store` override resolution,
- `store.json` loading/validation.

### `AFTK/Source.lean`

- source schema,
- JSON codecs,
- validation,
- load/save helpers.

### `AFTK/Packet.lean`

- packet schema,
- markdown body helpers,
- validation,
- load/save helpers.

### `AFTK/Knowledge.lean`

- knowledge schema,
- link/provenance validation,
- markdown body helpers,
- load/save helpers.

### `AFTK/Query.lean`

- list/filter/query logic over sources, packets, and knowledge entries,
- deterministic result ordering,
- JSON rendering for query output.

### `AFTK/Cli.lean`

- argument parsing,
- command dispatch,
- plain text / JSON output,
- error rendering.

## 13.3 Informalize integration

The knowledge base should integrate with existing Informalize types where that helps, but without entangling the two CLIs.

Recommended integration point for v1:

- `KnowledgeEntry.scaffoldRefs : Array Informalize.LocationId`

Recommended deferred integration:

- automatic validation/sync of Informalize metadata `knowledgeRefs` against knowledge-entry ids.

This keeps v1 useful without turning it into a cross-tool synchronization project.

---

## 14. Detailed implementation plan

## Phase 0: finalize schema and CLI contract

Deliverables:

- settled store root/layout,
- settled id families,
- settled record schemas,
- settled initial CLI surface,
- settled error model.

This document is Phase 0.

## Phase 1: core store and id infrastructure

Tasks:

1. Add `AFTKCli.lean` and `lean_exe aftk`.
2. Implement typed id parsing/rendering/path derivation.
3. Implement store discovery and `store init`.
4. Implement canonical JSON writing and atomic file persistence helpers.
5. Add `store validate` and `store stats`.

Acceptance:

- `lake exe aftk store init` creates a valid empty store,
- ids and paths are validated centrally,
- the CLI can discover the store from subdirectories.

## Phase 2: source registry

Tasks:

1. Define `SourceKind`, `SourceLocator`, `SourceRecord`.
2. Implement JSON codecs and validation.
3. Implement source load/save/list helpers.
4. Add CLI commands:
   - `source register`
   - `source show`
   - `source list`
   - `source validate`
   - `source update`
   - `source remove`
5. Ensure plain-text and JSON outputs.

Acceptance:

- sources can be registered and queried from the CLI,
- invalid source metadata is rejected clearly,
- source records are written canonically.

## Phase 3: source packets

Tasks:

1. Define packet anchors and packet provenance schema.
2. Define `SourcePacket` and packet markdown-body conventions.
3. Implement `packet ingest` from an existing file path.
4. Implement packet load/save/list/validate helpers.
5. Add CLI commands:
   - `packet ingest`
   - `packet show`
   - `packet list`
   - `packet validate`
   - `packet update`
   - `packet remove`

Important v1 limitation:

- `packet ingest` should copy or normalize from an already prepared text/markdown file,
- it does not need to solve PDF/OCR/document parsing.

Acceptance:

- packet metadata and packet body are persisted separately,
- packets can be queried by source id,
- packet provenance remains explicit.

## Phase 4: knowledge entries

Tasks:

1. Define `KnowledgeBasis`, `KnowledgeKind`, `ProvenanceRef`, `KnowledgeLink`, `KnowledgeEntry`.
2. Implement validation rules for:
   - basis,
   - references,
   - links,
   - scaffold refs.
3. Implement knowledge entry load/save/list helpers.
4. Add CLI commands:
   - `kb create`
   - `kb show`
   - `kb list`
   - `kb validate`
   - `kb update`
   - `kb remove`
   - `kb add-link` / `kb remove-link`
   - `kb add-tag` / `kb remove-tag`
   - `kb add-scaffold-ref` / `kb remove-scaffold-ref`

Acceptance:

- source-backed and derived knowledge entries can both be represented,
- knowledge entries can cite packets/sources explicitly,
- knowledge entries can link to scaffold nodes.

## Phase 5: query engine

Tasks:

1. Implement deterministic scan-based queries.
2. Add filter support for kind/basis/tag/source/packet/location/related/text.
3. Add `kb query` JSON output suitable for agents.
4. Ensure output stays bounded and stable; support `--limit` from the beginning.

Acceptance:

- agents can retrieve relevant knowledge entries without manually traversing files,
- results are deterministic and machine-readable.

## Phase 6: consistency checks and cross-reference validation

Tasks:

1. Strengthen store-wide validation:
   - missing referenced ids,
   - dangling links,
   - unsafe removals,
   - malformed sidecars.
2. Add optional checks involving Informalize references, such as:
   - scaffold refs parse as valid location ids,
   - future: validate `informal/...json` knowledge refs against `kb.*` ids.

Acceptance:

- the store can be validated as a coherent graph rather than only record-by-record.

## Phase 7: documentation and examples

Because `AGENTS.md` requires documentation updates alongside project changes, the implementation PR must update the relevant docs when code lands.

Minimum docs to review/update when implementation happens:

- `README.md`
- `docs/aftk/README.md`
- `docs/agent-playbook.md`
- `docs/future/autoformalization-tools.md`
- `docs/workflow.md`
- `docs/components.md`
- `docs/informalize/README.md` if Informalize integration behavior changes

Docs should explain:

- store layout,
- source registration,
- packet ingestion,
- knowledge entry creation,
- query flows,
- provenance model,
- relationship to Informalize `knowledgeRefs`.

## Phase 8: tests

Add unit and integration coverage throughout the phases rather than waiting until the end.

---

## 15. Test plan

## 15.1 Unit tests

Add tests for:

- id parsing/rendering/path derivation,
- source/packet/knowledge JSON codecs,
- validation invariants,
- markdown-sidecar path helpers,
- store discovery logic,
- deterministic query filtering.

## 15.2 CLI integration tests

Add runtime CLI tests similar in style to `Tests/Integration/Cli.lean`.

Recommended new file:

- `Tests/Integration/AFTKCli.lean`

Test cases should include:

1. `store init`
2. `source register` + `source show`
3. `packet ingest` + `packet show`
4. `kb create` + `kb show`
5. `kb query` by kind/tag/source/location
6. invalid source-backed entry rejected without provenance
7. missing referenced packet/source rejected
8. removal blocked when references still exist
9. `--json` output shape checks

## 15.3 Fixture strategy

Recommended fixture structure:

- small runtime-created test store under `aftk-data/` in test-only locations,
- a few static invalid fixtures for negative parsing/validation tests.

## 15.4 Regression coverage for canonical writes

Add tests to ensure:

- repeated writes are stable,
- JSON field ordering remains canonical,
- markdown bodies are written where expected,
- update commands do not accidentally erase unrelated fields.

---

## 16. Acceptance criteria

The knowledge-base infrastructure is complete when all of the following hold.

### Core storage behavior

1. A repository-local AFTK store can be initialized explicitly.
2. Source ids, packet ids, and knowledge ids are validated and path-resolved consistently.
3. Sources, packets, and knowledge entries are persisted canonically on disk.
4. Long-form packet/knowledge content is stored in markdown sidecars.

### Source/provenance behavior

5. Sources can be registered and shown through the CLI.
6. Packets can be ingested from prepared text/markdown files and shown through the CLI.
7. Knowledge entries can explicitly distinguish `source_backed` from `derived`.
8. Source-backed entries must carry explicit source/packet provenance.

### Query behavior

9. Agents can query knowledge entries by structured filters.
10. Query output is available in JSON.
11. Results are deterministic.

### Integration behavior

12. Knowledge entries can refer to Informalize scaffold locations.
13. The design is compatible with existing `kb.*` references in Informalize metadata.

### Quality behavior

14. Validation catches malformed or dangling references clearly.
15. Tests cover the main happy-path and failure-path CLI behaviors.
16. Repository docs are updated when the code implementation lands.

---

## 17. Risks and mitigations

## 17.1 Risk: over-scoping the first version into a full workflow engine

Mitigation:

- keep v1 focused on storage/query/writeback infrastructure,
- explicitly defer orchestration, readiness, and automated extraction.

## 17.2 Risk: CLI write surface becomes too wide and awkward

Mitigation:

- support `--from-json <File>` for complex records,
- keep common mutations as dedicated subcommands,
- keep output schemas stable.

## 17.3 Risk: provenance becomes optional in practice

Mitigation:

- make provenance validation strict for `source_backed` entries,
- expose store-wide validation commands early.

## 17.4 Risk: file-backed query becomes slow later

Mitigation:

- start with scan-based queries for correctness,
- leave room for derived indexes in a later phase without changing user-facing ids.

## 17.5 Risk: cross-linking with Informalize becomes inconsistent

Mitigation:

- keep integration narrow in v1,
- validate scaffold refs structurally,
- add explicit future sync/consistency tooling rather than hidden side effects.

## 17.6 Risk: arbitrary source ingestion expectations exceed Lean-only MVP scope

Mitigation:

- clearly scope `packet ingest` to prepared text/markdown inputs in v1,
- treat richer ingestion pipelines as future work.

---

## 18. Open questions to resolve before implementation starts

1. Should `lake exe aftk` be introduced now as a general umbrella CLI, or should the executable be named something narrower such as `aftk_kb`?
   - Recommendation: use `aftk` now.

2. Should `source update` / `packet update` / `kb update` be granular flag-based mutations, whole-record replacement from JSON, or both?
   - Recommendation: both, with `--from-json` for complex inputs.

3. Should the store root be `aftk-data/` or something hidden like `.aftk/`?
   - Recommendation: `aftk-data/` for visibility and git inspectability.

4. Should packet and knowledge sidecars always be markdown, or should plain-text sidecars also be supported?
   - Recommendation: markdown-only in v1 unless plain-text support becomes necessary.

5. Should store validation reject all dangling references immediately, including links to not-yet-created intended ids?
   - Recommendation: yes for committed records; agents should create referenced records explicitly.

---

## 19. Recommended implementation order

Recommended order of work:

1. `aftk` executable + store discovery/init,
2. typed ids + filesystem/path helpers,
3. source registry,
4. source packets,
5. knowledge entries,
6. query engine,
7. store-wide validation,
8. docs/tests polish.

This order keeps the implementation aligned with the workflow’s source-first requirements.

---

## 20. Summary

The repository already has:

- a blueprint layer (`Informalize`), and
- a Lean-local execution layer (`AFTK` hub tools).

The main missing framework layer is now the **knowledge base**.

The recommended next step is to build a **new Lean CLI** under `lake exe aftk ...` with a **file-backed repository-local store** rooted at `aftk-data/`, supporting:

- source registration,
- source-packet persistence,
- knowledge entry persistence,
- provenance and linking,
- deterministic agent-facing queries,
- incremental writeback.

That provides the missing infrastructure needed to make the documented workflow materially real inside the repository, while staying small enough for a practical first implementation.
