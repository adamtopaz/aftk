module

public import AFTK.Informal

public section


set_option aftk.informal.root "tests/informal/knowledgebase-fixtures/basic-valid"

namespace AFTKTest.Informal.Fixtures.Deps.Cycle

noncomputable section

mutual
  partial def cycleA (n : Nat) : Nat :=
    if n = 0 then
      informal[group.basic.definition]
    else
      cycleB (n - 1)

  partial def cycleB (n : Nat) : Nat :=
    if n = 0 then
      informal[group.basic.operation_note]
    else
      cycleA (n - 1)
end

end

end AFTKTest.Informal.Fixtures.Deps.Cycle
