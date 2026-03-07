# Informalize ID Reference

This document defines how `informal[<id>]` location ids map to markdown files.

---

## Syntax forms

```lean
informal a b c
informal[Foo.bar] a b c
informal[Foo.bar.baz] a b c
```

- `informal ...` is valid and does **not** perform markdown lookup.
- `informal[<id>] ...` resolves `<id>` to a file under `informal/`.

`informal` is still a regular Lean term, so these forms can be used as typed placeholders
inside terms/proofs during gradual refinement.

---

## Mapping rule

`<id>` is dotted (`A.B.C...`) and maps as:

- all but the final component become directories,
- final component becomes `<name>.md`.

Examples:

- `Foo.bar` -> `informal/Foo/bar.md`
- `Foo.bar.baz` -> `informal/Foo/bar/baz.md`
- `Alpha.root.child.grandchild` -> `informal/Alpha/root/child/grandchild.md`

Validation happens during elaboration.

---

## Validity constraints

For `informal[<id>]`:

1. at least two components are required (`Directory.File`),
2. numeric name components are rejected,
3. resolved markdown file must exist and be readable.

Typical failures:

- too short: `informal[Foo]`
- missing file: `informal[Missing.bar]`

---

## Tracking behavior

Each declaration containing `informal` is tracked by Informalize.

For each tracked declaration, Informalize stores a deduplicated set of location ids.

- bare `informal ...` contributes an empty location set,
- repeated `informal[Foo.bar]` in one declaration still records `Foo.bar` once.

### Hover integration with AFTK

When hovering at an `informal[...]` occurrence, AFTK hover queries can surface the
associated markdown/natural-language content for that id.

In practice, agents usually do this via `aftk_get_hover` exposed by the AFTK pi extension wrapper or by the shared custom toolset.

This is useful for agent workflows that alternate between:

- tactic exploration in Lean, and
- reading/writing strategy notes in `informal/.../*.md`.

---

## Querying tracked ids

Use the CLI:

```bash
lake exe informalize status --module <Module.Name>
lake exe informalize deps --module <Module.Name>
lake exe informalize decls --module <Module.Name>
lake exe informalize decl --module <Module.Name> --decl <Decl.Name>
lake exe informalize locations --module <Module.Name>
lake exe informalize location --module <Module.Name> --location <Location.Name>
```

`deps` computes transitive dependency reachability and reports relations among tracked declarations only.

---

## Naming recommendations

For long-term blueprint maintenance:

- use stable hierarchical namespaces (`Domain.Topic.Statement`),
- keep ids semantically meaningful,
- avoid renaming ids unless necessary (renames move markdown paths).
