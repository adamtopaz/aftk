module

public import AFTK.KnowledgeBase.Cli.Main
public import AFTK.Informal.Cli.Main

public section


private def topLevelUsage : String :=
  "Usage: lake exe aftk_cli <command> ..."

private def topLevelHelp : String :=
  String.intercalate "\n\n" [
    String.intercalate "\n" [
      "Usage:",
      "  lake exe aftk_cli <command> ..."
    ],
    "Top-level entrypoint for AFTK.",
    String.intercalate "\n" [
      "Options:",
      "  --help                Show this help text"
    ],
    String.intercalate "\n" [
      "Commands:",
      "  knowledgebase         Manage the AFTK knowledge base",
      "  informal              Query the AFTK informal layer"
    ],
    "Run `lake exe aftk_cli knowledgebase --help` for knowledgebase command help.",
    "Run `lake exe aftk_cli informal --help` for informal command help."
  ]

unsafe def main (args : List String) : IO Unit := do
  match args with
  | ["--help"] =>
      IO.println topLevelHelp
      IO.Process.exit 0
  | "knowledgebase" :: rest =>
      AFTK.KnowledgeBase.Cli.Main.main rest
  | "informal" :: rest =>
      AFTK.Informal.Cli.Main.main rest
  | _ =>
      IO.eprintln topLevelUsage
      IO.Process.exit 2
