import AFTK.Informal

set_option aftk.informal.root "tests/informal/knowledgebase-fixtures/basic-valid"

namespace AFTKTest.Informal.Fixtures.Imports.Base

noncomputable section

def baseTracked : Nat :=
  informal[group.basic.definition]

def baseHelper : Nat :=
  baseTracked + 1

end

end AFTKTest.Informal.Fixtures.Imports.Base
