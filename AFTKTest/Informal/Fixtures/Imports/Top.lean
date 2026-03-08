import AFTKTest.Informal.Fixtures.Imports.Mid

namespace AFTKTest.Informal.Fixtures.Imports.Top

open AFTKTest.Informal.Fixtures.Imports.Mid

noncomputable section

def topTracked : Nat :=
  midTracked + 1

end

end AFTKTest.Informal.Fixtures.Imports.Top
