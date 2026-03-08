import AFTK.KnowledgeBase.Storage

namespace AFTK.KnowledgeBase

open Lean

namespace Indexing

structure IndexStatus where
  available : Bool := false
  stale : Bool := false
  deriving Repr, DecidableEq, Inhabited

instance : ToJson IndexStatus where
  toJson status := Json.mkObj [
    ("available", toJson status.available),
    ("stale", toJson status.stale)
  ]

end Indexing

end AFTK.KnowledgeBase
