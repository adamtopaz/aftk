module

public import Lean

public section

namespace Informalize

/--
Unsound placeholder axiom used during gradual formalization.
`tag` is a unique name used to keep placeholders distinct.
-/
axiom Informal.{u} (tag : Lean.Name) (alpha : Sort u) : alpha

end Informalize
