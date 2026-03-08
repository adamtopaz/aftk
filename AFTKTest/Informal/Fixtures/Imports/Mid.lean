import AFTKTest.Informal.Fixtures.Imports.Base
import AFTK.Informal

set_option aftk.informal.root "tests/informal/knowledgebase-fixtures/basic-valid"

namespace AFTKTest.Informal.Fixtures.Imports.Mid

open AFTKTest.Informal.Fixtures.Imports.Base

noncomputable section

def midTracked : Nat :=
  baseHelper + informal[algebra.monoid.definition]

end

end AFTKTest.Informal.Fixtures.Imports.Mid
