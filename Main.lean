import AFTK.KnowledgeBase.Cli.Main

private def topLevelUsage : String :=
  "Usage: lake exe aftk knowledgebase [options] <command> ..."

def main (args : List String) : IO Unit := do
  match args with
  | "knowledgebase" :: rest =>
      AFTK.KnowledgeBase.Cli.Main.main rest
  | _ =>
      IO.eprintln topLevelUsage
      IO.Process.exit 2
