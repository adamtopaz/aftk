import AFTK

set_option aftk.informal.root "tests/informal/knowledgebase-fixtures/basic-valid"

namespace AFTKTest.Informal.Fixtures.Basic

noncomputable section

def oneRef : Nat :=
  informal[group.basic.definition]

def anotherOneRef : Nat :=
  informal[group.basic.definition]

def repeatedRef : Nat :=
  informal[group.basic.definition] + informal[group.basic.definition]

def multiRef : Nat :=
  informal[group.basic.definition] + informal[group.basic.operation_note]

def appliedRef (n : Nat) : Nat :=
  informal[algebra.monoid.definition] n

def oneSegmentRef : Nat :=
  informal[group]

def theoremWithRef : True := by
  exact informal[proof.sketch]

def typePlaceholder : Type :=
  informal[group]

end

end AFTKTest.Informal.Fixtures.Basic
