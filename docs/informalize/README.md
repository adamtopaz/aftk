# Informalize: Blueprint Layer for Gradual Autoformalization

Informalize is the part of AFTK used to construct and query an **informal blueprint** of a formalization project.

The blueprint is an **intermediate organizational step**:

- start from high-level mathematical structure,
- connect declarations to natural-language descriptions,
- track dependencies while formal content is still incomplete,
- progressively refine toward direct Lean formalization.

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

- `informal[... ]` attaches to a markdown location id.
- `informal ...` (without brackets) is still tracked, but has no location id.

`informal` is a regular Lean term, so it can be used as a typed placeholder inside
proofs and definitions while refinement is in progress (similar in workflow spirit to `sorry`).

`informal[Foo.bar]` resolves to:

- `informal/Foo/bar.md`

`informal[Foo.bar.baz]` resolves to:

- `informal/Foo/bar/baz.md`

If the resolved file is missing/unreadable, elaboration fails.

---

## Natural-language attachment

The markdown file content is treated as the natural-language component of that blueprint location.

This enables a declaration to carry:

- Lean-level placeholder position,
- location id for tracking,
- associated human-readable math description.

### AFTK integration (important)

Informalize is intended to be used together with AFTK hub tools.

In particular, agents can query hover at an `informal[...]` term and recover the
attached natural-language markdown context through AFTK (`get_hover` / `aftk_get_hover`).

In the recommended `lambda` runner, `aftk_get_hover` is built in.
(`lambda` loads `lambda.json`, creates a pi SDK session, and runs a separately provided prompt in print mode.)
Upstream `pi` can still access it through the compatibility extension.

This gives a direct bridge from blueprint notes to local proof exploration.

---

## What Informalize records

Informalize stores extension data keyed by declaration name:

- declaration name,
- deduplicated set of referenced location ids.

If a declaration uses only bare `informal`, it is tracked with an empty location set.

This provides the foundation for project-wide blueprint queries.

---

## CLI: Query blueprint state (agent-facing)

```bash
lake exe informalize <command> --module <Module.Name> [options]
```

Commands:

- `status` — summary counts of tracked declarations/locations
- `deps` — transitive dependency graph among tracked declarations + leaves
- `decls` — list tracked declarations (supports filters)
- `decl` — show one declaration’s location set
- `locations` — reverse index location -> declarations
- `location` — declarations referencing one location

Useful options:

- `-m, --module <Module.Name>` (required, repeatable)
- `--decl <Decl.Name>` (required for `decl`)
- `--location <Location.Name>` (required for `location`)
- `--bare-only` / `--with-locations` (for `decls`)

Examples:

```bash
lake exe informalize status --module Tests.Integration.Imports.Top
lake exe informalize deps --module Tests.Integration.Deps
lake exe informalize decls --module Tests.Integration.Imports.Top --with-locations
lake exe informalize decl --module Tests.Integration.Imports.Top --decl Tests.Integration.Imports.Base.baseLoc
lake exe informalize locations --module Tests.Integration.Imports.Top
lake exe informalize location --module Tests.Integration.Imports.Top --location Foo.bar
```

## Testing note

Integration assertions for this CLI live in `Tests/Integration/Cli.lean` and are
executed at runtime via `lake exe tests` (instead of compile-time `run_cmd`).
This keeps CI build memory usage stable while preserving CLI coverage.

---

## Dependency interpretation (`deps`)

`deps` computes transitive constant-usage reachability, then projects back onto declarations tracked by Informalize.

This means traversal may pass through intermediate declarations that are not themselves tracked, while output stays focused on tracked declarations.

`Leaves` are tracked declarations with no tracked dependencies in that projected transitive graph.

---

## Suggested gradual-refinement loop

1. Create high-level declarations using `informal[...]` and markdown notes.
2. Run CLI (`status`, `deps`, `locations`) to inspect blueprint state.
3. Prioritize frontier items (often leaves or high-impact dependencies).
4. Use AFTK tools to inspect context and explore tactics transiently.
5. During exploration, write/update natural-language strategy notes in the linked markdown file.
6. Convert successful exploration into concrete Lean definitions/proofs.
7. Repeat until blueprint placeholders disappear.

This Informalize+AFTK loop is the intended agent workflow.

---

## Soundness note

`informal` elaborates through the unsound axiom:

```lean
axiom Informalize.Informal.{u} (tag : Lean.Name) (alpha : Sort u) : alpha
```

So blueprint declarations are planning artifacts, not finished formal results.

---

## See also

- Id rules: `docs/informalize/IdReference.md`
- Project overview: `README.md`
- AFTK hub docs: `docs/aftk/README.md`
