# Informal Id Reference

`informal[<id>] ...args` uses dotted ids.

- `informal a b c` is valid and does not check markdown locations.
- `informal[Foo.bar] a b c` checks markdown location at elaboration time.

- `Foo.bar` -> `informal/Foo/bar.md`
- `Foo.bar.baz` -> `informal/Foo/bar/baz.md`
- deeper ids continue as nested directories, with the final component as `<name>.md`

Validation happens during elaboration.

Each successful elaboration is tracked in an environment extension keyed by
declaration name, with a deduplicated location set for that declaration.

You can inspect this data with the CLI:

- `lake exe informalize status --module <Module.Name>`
- `lake exe informalize deps --module <Module.Name>`
- `lake exe informalize decls --module <Module.Name>`
- `lake exe informalize decl --module <Module.Name> --decl <Decl.Name>`
- `lake exe informalize locations --module <Module.Name>`
- `lake exe informalize location --module <Module.Name> --location <Location.Name>`

`deps` computes transitive dependencies using `ConstantInfo.getUsedConstantsAsSet`.
Traversal may pass through declarations that do not contain `informal`; output only
shows dependencies between declarations tracked by the informal extension.

`Leaves` in `deps` output are tracked declarations with no tracked dependencies.
