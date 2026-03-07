# Informalize: Blueprint Layer for Gradual Autoformalization

Informalize is the part of AFTK used to construct and query an **informal blueprint** of a formalization project.

The blueprint is an **intermediate organizational step**:

- start from high-level mathematical structure,
- connect declarations to natural-language descriptions,
- track dependencies while formal content is still incomplete,
- progressively refine toward direct Lean formalization.

Within the broader workflow in `docs/workflow.md`, Informalize is the scaffold-management layer that sits between source/knowledge preparation and Lean-level formalization.

---

## Why use a blueprint first?

In large autoformalization tasks, the main bottleneck is often project organization:

- what should be formalized first,
- which declarations depend on which others,
- where natural-language intent lives,
- which items are still placeholders.

Informalize makes this explicit and queryable.

---

## Core syntax

```lean
informal[Foo.bar]
informal[Foo.bar] x y
informal[Foo.bar.baz] x y
informal x y
```

Semantics:

- `informal[... ]` attaches to a markdown-backed location id.
- `informal ...` (without brackets) is still tracked, but has no location id.

`informal` is a regular Lean term, so it can be used as a typed placeholder inside
proofs and definitions while refinement is in progress (similar in workflow spirit to `sorry`).

`informal[Foo.bar]` resolves to:

- required markdown: `informal/Foo/bar.md`
- optional metadata sidecar: `informal/Foo/bar.json`

`informal[Foo.bar.baz]` resolves to:

- required markdown: `informal/Foo/bar/baz.md`
- optional metadata sidecar: `informal/Foo/bar/baz.json`

If the markdown file is missing/unreadable, elaboration fails.
If the JSON sidecar is missing, Informalize uses default metadata.
If the JSON sidecar exists but is invalid/unreadable, elaboration fails.

---

## Natural-language attachment

The markdown file content is treated as the natural-language component of that blueprint location.
Optional JSON sidecars provide structured workflow metadata such as status, parent links,
source refs, issues, and tags.

This enables a declaration to carry:

- Lean-level placeholder position,
- location id for tracking,
- associated human-readable math description,
- effective machine-readable scaffold metadata.

### AFTK integration (important)

Informalize is intended to be used together with AFTK hub tools.

In particular, agents can query hover at an `informal[...]` term and recover the
attached natural-language markdown context together with the effective metadata summary
through AFTK (`get_hover` / `aftk_get_hover`).

`aftk_get_hover` is exposed by both AFTK TypeScript surfaces:

- the shared custom toolset from `lambda/src/aftk-tools.ts`, and
- the upstream `pi` extension wrapper at `lambda/src/aftk-extension.ts`.

This gives a direct bridge from blueprint notes to local proof exploration.

---

## What Informalize records

Informalize stores extension data keyed by declaration name:

- declaration name,
- deduplicated set of referenced location ids.

If a declaration uses only bare `informal`, it is tracked with an empty location set.
The structured metadata sidecar is separate from this extension state:

- declaration/location usage is tracked automatically by the extension,
- workflow metadata is stored in optional `informal/.../*.json` sidecars,
- dependency relations are derived automatically rather than persisted in metadata.

This provides the foundation for project-wide blueprint queries.

---

## CLI: Query blueprint state (agent-facing)

```bash
lake exe informalize <command> --module <Module.Name> [options]
```

Commands:

- `status` — summary counts of tracked declarations/locations
- `deps` — transitive dependency graph among tracked declarations, or derived location dependencies with `--by location`
- `decls` — list tracked declarations (supports filters)
- `decl` — show one declaration’s location set
- `locations` — reverse index location -> declarations
- `location` — declarations referencing one location
- `meta show` — show effective metadata for one location
- `meta validate` — validate effective metadata for one location
- `meta init` — materialize default metadata JSON for one location
- `meta set-status`, `meta set-parent`, `meta clear-parent`, `meta set-kind`, `meta clear-kind`
- `meta add/remove-tag`, `meta add/remove-knowledge-ref`, `meta add/remove-source`, `meta add/remove-issue`

Useful options:

- `-m, --module <Module.Name>` (required, repeatable, for non-`meta` commands)
- `--decl <Decl.Name>` (required for `decl`)
- `--location <Location.Name>` (required for `location` and `meta` commands)
- `--by decl|location` (for `deps`)
- `--bare-only` / `--with-locations` (for `decls`)
- `--json` (machine-readable output)

Examples:

```bash
lake exe informalize status --module Tests.Integration.Imports.Top
lake exe informalize deps --module Tests.Integration.Deps
lake exe informalize deps --module Tests.Integration.Imports.Top --by location
lake exe informalize decls --module Tests.Integration.Imports.Top --with-locations
lake exe informalize decl --module Tests.Integration.Imports.Top --decl Tests.Integration.Imports.Base.baseLoc
lake exe informalize locations --module Tests.Integration.Imports.Top
lake exe informalize location --module Tests.Integration.Imports.Top --location Foo.bar
lake exe informalize meta show --location Foo.bar
lake exe informalize meta set-status --location Foo.bar --status ready
```

Agents are expected to manage metadata through the CLI rather than by editing JSON sidecars directly.
If no sidecar exists yet, Informalize uses default metadata and the first metadata mutation command creates the JSON file.

## Testing note

Integration assertions for this CLI live in `Tests/Integration/Cli.lean` and are
executed at runtime via `lake exe tests` (instead of compile-time `run_cmd`).
This keeps CI build memory usage stable while preserving CLI coverage.

---

## Dependency interpretation (`deps`)

`deps --by decl` computes transitive constant-usage reachability, then projects back onto declarations tracked by Informalize.

This means traversal may pass through intermediate declarations that are not themselves tracked, while output stays focused on tracked declarations.

`deps --by location` projects those declaration dependencies onto informal locations:

1. find tracked declarations referencing a location,
2. compute their transitive tracked declaration dependencies,
3. collect the locations referenced by those dependent declarations,
4. union them and remove the source location itself.

`Leaves` are nodes with no dependencies in the selected view.

---

## Suggested gradual-refinement loop

Within the broader workflow in `docs/workflow.md`, Informalize mainly handles scaffold construction, frontier inspection, and local refinement.

1. Create or refine declarations using `informal[...]` and markdown notes.
2. Inspect/query metadata with CLI (`meta show`, `meta validate`) and update it through CLI mutations rather than manual JSON edits.
3. Run CLI (`status`, `deps`, `locations`) to inspect blueprint state and derived dependencies.
4. Prioritize frontier items (often leaves or high-impact dependencies).
5. Decide whether a frontier item needs more sources, more scaffold refinement, or direct formalization.
6. When the item is ready, use AFTK tools to inspect context and explore tactics transiently.
7. During exploration, write/update natural-language strategy notes in the linked markdown file and use CLI metadata commands for structured status/source updates.
8. Convert successful exploration into concrete Lean definitions/proofs.
9. Repeat until blueprint placeholders disappear.

This Informalize+AFTK loop is the intended local scaffold/formalization workflow, not the entire source-ingestion pipeline.

---

## Soundness note

`informal` elaborates through the unsound axiom:

```lean
axiom Informalize.Informal.{u} (tag : Lean.Name) (alpha : Sort u) : alpha
```

So blueprint declarations are planning artifacts, not finished formal results.

---

## See also

- End-to-end workflow: `docs/workflow.md`
- Framework components: `docs/components.md`
- Id rules: `docs/informalize/IdReference.md`
- Project overview: `README.md`
- AFTK hub docs: `docs/aftk/README.md`
