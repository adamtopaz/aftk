# Informalize

Informalize is now a minimal Lean 4 rewrite centered on a single term elaborator:

```lean
informal[Foo.bar]
informal[Foo.bar] x y
informal[Foo.bar.baz] x y
informal x y
```

When location is provided, dotted ids resolve directly to markdown file paths:
`Foo.bar` -> `informal/Foo/bar.md`, `Foo.bar.baz` -> `informal/Foo/bar/baz.md`.

If the resolved file does not exist (or cannot be read), elaboration fails.
Location is optional: plain `informal ...` skips markdown lookup.

## Core behavior

- `informal` is term-only.
- `informal` is only allowed inside declaration types/values (including proofs).
- location is optional and written as `informal[Foo.bar...]`.
- each use elaborates to an unsound placeholder based on:

```lean
axiom Informalize.Informal.{u} (tag : Lean.Name) (alpha : Sort u) : alpha
```

The elaborator generates a unique `Lean.Name` tag (similar to sorry labels), then
builds an expression equivalent to `Informal <unique_name> ...` with any provided
arguments.

The environment extension tracks declarations that contain `informal` and stores
the deduplicated set of markdown locations referenced in each declaration (possibly
empty when only `informal ...` without brackets is used).

## Repository layout

- `Informalize/Axiom.lean`
- `Informalize/Elaborator.lean`
- `informal/` markdown snippets referenced by ids
- `Tests/Unit/*` rewrite test modules

## Build and tests

```bash
lake build
lake build informalize
lake exe tests
```

## CLI queries

Query extension data outside Lean files with:

```bash
lake exe informalize status --module Tests.Integration.Imports.Top
lake exe informalize deps --module Tests.Integration.Deps
lake exe informalize decls --module Tests.Integration.Imports.Top --with-locations
lake exe informalize decl --module Tests.Integration.Imports.Top --decl Tests.Integration.Imports.Base.baseLoc
lake exe informalize locations --module Tests.Integration.Imports.Top
lake exe informalize location --module Tests.Integration.Imports.Top --location Foo.bar
```

Command overview:

- `status`: summary counts for tracked declarations and markdown locations.
- `deps`: transitive dependency graph among tracked declarations, plus leaves.
- `decls`: list tracked declarations with location counts and location sets.
- `decl`: show one declaration's tracked location set.
- `locations`: reverse index from location to declarations.
- `location`: show declarations referencing one location.

`deps` follows constant usage transitively through non-informal bridge declarations,
then projects results back onto declarations tracked by the informal extension.
Leaves are tracked declarations with no tracked dependencies in that transitive graph.

See also: `docs/informalize/IdReference.md`.
