import Informalize

noncomputable def nestedSection : Nat :=
  informal[Foo.bar.baz]

noncomputable def nestedSectionWithArgs (x y : Nat) : Nat :=
  informal[Foo.bar.baz] x y

noncomputable def deeperNestedSection : Nat :=
  informal[Alpha.root.child.grandchild]
