module

public import AFTK.Informal

public section


set_option aftk.informal.root "tests/informal/knowledgebase-fixtures/basic-valid"

def invalidNodeId : Nat :=
  informal[Group.basic.definition]
