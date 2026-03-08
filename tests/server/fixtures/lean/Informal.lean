import AFTK.Informal

set_option aftk.informal.root "tests/server/fixtures/knowledgebase/basic-valid"

namespace AFTKTest.Server.Fixtures

def informalTarget : Nat := informal[group.basic.definition]

end AFTKTest.Server.Fixtures
