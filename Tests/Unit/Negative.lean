import Informalize

/--
error: informal id `Foo` must have at least two components (`Directory.File`)
-/
#guard_msgs(error, drop warning) in
example : Nat :=
  informal[Foo]

/--
error: informal id `Missing.bar` points to missing file `informal/Missing/bar.md`
-/
#guard_msgs(error, drop warning) in
example : Nat :=
  informal[Missing.bar]

/--
error: informal id `Foo.missing` points to missing file `informal/Foo/missing.md`
-/
#guard_msgs(error, drop warning) in
example : Nat :=
  informal[Foo.missing]

/--
error: informal id `Foo.bar.nope` points to missing file `informal/Foo/bar/nope.md`
-/
#guard_msgs(error, drop warning) in
example : Nat :=
  informal[Foo.bar.nope]

/--
error: `informal` may only be used inside declaration values or proofs
-/
#guard_msgs(error, drop warning) in
#check informal 1 2
