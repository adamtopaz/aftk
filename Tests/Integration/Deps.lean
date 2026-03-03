import Informalize

namespace Tests.Integration.Deps

noncomputable def first : Nat :=
  informal[Foo.bar]

noncomputable def step1 : Nat :=
  first

noncomputable def step2 : Nat :=
  step1

noncomputable def step3 : Nat :=
  step2

noncomputable def step4 : Nat :=
  step3

noncomputable def last : Nat :=
  informal[Alpha.root.child.grandchild] step4

noncomputable def isolated : Nat :=
  informal

end Tests.Integration.Deps
