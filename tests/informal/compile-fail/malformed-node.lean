module

public import AFTK.Informal

public section


set_option aftk.informal.root "tests/informal/knowledgebase-fixtures/malformed-node"

def malformedNode : Nat :=
  informal[broken.node]
