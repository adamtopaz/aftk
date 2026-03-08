module

public import Lean

public section

namespace AFTK.Informal

register_option aftk.informal.root : String := {
  defValue := ""
  descr := "Override the knowledge-base root used by AFTK informal elaboration"
}

end AFTK.Informal
