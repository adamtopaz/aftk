import Informalize

noncomputable def basicNat : Nat :=
  informal[Foo.bar]

noncomputable def basicNatWithArg (n : Nat) : Nat :=
  informal n

theorem basicProof : True := by
  exact informal

noncomputable def uniqLeft : Nat :=
  informal[Foo.bar]

noncomputable def uniqRight : Nat :=
  informal[Foo.bar]

example : True := by
  fail_if_success
    have : uniqLeft = uniqRight := by
      rfl
  exact True.intro
