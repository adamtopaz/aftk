import AFTK.Informal

set_option aftk.informal.root "tests/informal/knowledgebase-fixtures/basic-valid"

def missingNode : Nat :=
  informal[missing.node]
