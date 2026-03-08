import Lean

namespace AFTK.Informal

/--
Unsound placeholder used during gradual formalization.
`tag` keeps different placeholder occurrences distinct.
-/
axiom Informal.{u} (tag : Lean.Name) (α : Sort u) : α

end AFTK.Informal
