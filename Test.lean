/-
A richer test file for AFTK file_worker.
Contains several independent goals and tactic styles.
-/

example (a b : Nat) : a + b = b + a := by
  rw [Nat.add_comm]

example (a b c : Nat) : (a + b) + c = a + (b + c) := by
  rw [Nat.add_assoc]

example (n : Nat) : n + 0 = n := by
  simpa using Nat.add_zero n

example (n : Nat) : 0 + n = n := by
  simpa using Nat.zero_add n

example (p q : Prop) : p ∧ q → q ∧ p := by
  intro h
  exact And.intro h.right h.left

example (p q r : Prop) : (p → q) → (q → r) → (p → r) := by
  intro hpq hqr hp
  exact hqr (hpq hp)

example (x y : Nat) : x = y → y = x := by
  intro h
  exact Eq.symm h

example (n : Nat) : Nat.succ n = n + 1 := by
  simpa using Nat.succ_eq_add_one n

example (α : Type) (x : α) : (fun y => y) x = x := by
  rfl
