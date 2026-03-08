import AFTK

set_option aftk.informal.root "tests/informal/knowledgebase-fixtures/basic-valid"

def invalidNodeId : Nat :=
  informal[Group.basic.definition]
