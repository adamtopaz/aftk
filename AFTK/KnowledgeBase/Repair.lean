import AFTK.KnowledgeBase.Validation

namespace AFTK.KnowledgeBase

open Lean

namespace Repair

structure RepairAction where
  code : String
  description : String
  deriving Repr, DecidableEq, Inhabited

instance : ToJson RepairAction where
  toJson action := Json.mkObj [
    ("code", toJson action.code),
    ("description", toJson action.description)
  ]

structure RepairPlan where
  actions : Array RepairAction := #[]
  deriving Repr, DecidableEq, Inhabited

instance : ToJson RepairPlan where
  toJson plan := Json.mkObj [("actions", toJson plan.actions)]

end Repair

end AFTK.KnowledgeBase
