import AFTK

namespace AFTKTest.Server.Fixtures

def hoverTarget : Nat := Nat.succ 0

def termGoalTarget : Nat :=
  1

theorem tacticTarget (n : Nat) : n + 0 = n := by
  simpa

theorem tacticStepsTarget (p q : Prop) : p ∧ q -> q ∧ p := by
  intro h
  exact And.intro h.right h.left

end AFTKTest.Server.Fixtures
