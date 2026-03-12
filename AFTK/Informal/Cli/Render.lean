module

public import AFTK.Informal.Cli.Types

public section


namespace AFTK.Informal
namespace Cli
namespace Render

open Lean
open AFTK.KnowledgeBase

private def commandName : Command → String
  | .status => "status"
  | .decls _ => "decls"
  | .decl _ => "decl"
  | .refs _ => "refs"
  | .ref _ => "ref"
  | .deps _ => "deps"
  | .present _ _ => "present"

private def depsModeName : DepsMode → String
  | .decl => "decl"
  | .ref => "ref"

private def presentModeName : PresentMode → String
  | .compact => "compact"
  | .rich => "rich"

private def bodyModeName : BodyRenderMode → String
  | .none => "none"
  | .preview => "preview"
  | .full => "full"

private def outputFormatName : OutputFormat → String
  | .text => "text"
  | .json => "json"

private def namesJson (names : Array Name) : Json :=
  toJson (names.map toString)

private def refsJson (refs : Array InformalReference) : Json :=
  toJson (refs.map toString)

private def declEntryJson (entry : InformalDeclEntry) : Json :=
  Json.mkObj [
    ("declName", toJson entry.declName.toString),
    ("refCount", toJson entry.refs.size),
    ("refs", refsJson entry.refs)
  ]

private def refEntryJson (entry : InformalReferenceEntry) : Json :=
  Json.mkObj [
    ("ref", toJson (toString entry.ref)),
    ("declCount", toJson entry.declNames.size),
    ("declNames", namesJson entry.declNames)
  ]

private def declDepsJson (rows : Array InformalDeclDependencyEntry) (leaves : Array Name) : Json :=
  Json.mkObj [
    ("rows", Json.arr <| rows.map fun row => Json.mkObj [
      ("declName", toJson row.declName.toString),
      ("dependencies", namesJson row.dependencies)
    ]),
    ("leaves", namesJson leaves)
  ]

private def refDepsJson (rows : Array InformalReferenceDependencyEntry) (leaves : Array InformalReference) : Json :=
  Json.mkObj [
    ("rows", Json.arr <| rows.map fun row => Json.mkObj [
      ("ref", toJson (toString row.ref)),
      ("dependencies", refsJson row.dependencies)
    ]),
    ("leaves", refsJson leaves)
  ]

private def statusText (info : StatusResult) : String :=
  String.intercalate "\n" [
    s!"Tracked declarations: {info.trackedDeclarations}",
    s!"Tracked references: {info.trackedReferences}",
    s!"Declarations with multiple references: {info.declarationsWithMultipleReferences}"
  ]

private def renderDeclEntryLine (entry : InformalDeclEntry) : String :=
  let refs := if entry.refs.isEmpty then "(none)" else String.intercalate ", " (entry.refs.toList.map toString)
  s!"- {entry.declName} [{entry.refs.size}]: {refs}"

private def renderRefEntryLine (entry : InformalReferenceEntry) : String :=
  let decls := if entry.declNames.isEmpty then "(none)" else String.intercalate ", " (entry.declNames.toList.map toString)
  s!"- {entry.ref} [{entry.declNames.size}]: {decls}"

private def declsText (entries : Array InformalDeclEntry) : String :=
  if entries.isEmpty then
    "Tracked declarations (0)"
  else
    String.intercalate "\n" <| [s!"Tracked declarations ({entries.size})"] ++ (entries.map renderDeclEntryLine).toList

private def refsText (entries : Array InformalReferenceEntry) : String :=
  if entries.isEmpty then
    "Tracked references (0)"
  else
    String.intercalate "\n" <| [s!"Tracked references ({entries.size})"] ++ (entries.map renderRefEntryLine).toList

private def declText (entry : InformalDeclEntry) : String :=
  String.intercalate "\n" [
    s!"Declaration: {entry.declName}",
    s!"Reference count: {entry.refs.size}",
    if entry.refs.isEmpty then "References: (none)" else s!"References: {String.intercalate ", " (entry.refs.toList.map toString)}"
  ]

private def refText (entry : InformalReferenceEntry) : String :=
  String.intercalate "\n" [
    s!"Reference: {entry.ref}",
    s!"Declaration count: {entry.declNames.size}",
    if entry.declNames.isEmpty then "Declarations: (none)" else s!"Declarations: {String.intercalate ", " (entry.declNames.toList.map toString)}"
  ]

private def declDepsText (rows : Array InformalDeclDependencyEntry) (leaves : Array Name) : String :=
  let rowLines := rows.map fun row =>
    let deps := if row.dependencies.isEmpty then "(none)" else String.intercalate ", " (row.dependencies.toList.map toString)
    s!"- {row.declName} -> {deps}"
  let leafLines := if leaves.isEmpty then ["- (none)"] else leaves.toList.map (fun leaf => s!"- {leaf}")
  String.intercalate "\n" <| [s!"Declaration dependencies ({rows.size})"] ++ rowLines.toList ++ ["", s!"Leaves ({leaves.size})"] ++ leafLines

private def refDepsText (rows : Array InformalReferenceDependencyEntry) (leaves : Array InformalReference) : String :=
  let rowLines := rows.map fun row =>
    let deps := if row.dependencies.isEmpty then "(none)" else String.intercalate ", " (row.dependencies.toList.map toString)
    s!"- {row.ref} -> {deps}"
  let leafLines := if leaves.isEmpty then ["- (none)"] else leaves.toList.map (fun leaf => s!"- {leaf}")
  String.intercalate "\n" <| [s!"Reference dependencies ({rows.size})"] ++ rowLines.toList ++ ["", s!"Leaves ({leaves.size})"] ++ leafLines

private def resultToText : CommandResult → String
  | .status info => statusText info
  | .decls entries => declsText entries
  | .decl entry => declText entry
  | .refs entries => refsText entries
  | .ref entry => refText entry
  | .declDeps rows leaves => declDepsText rows leaves
  | .refDeps rows leaves => refDepsText rows leaves
  | .presentCompact summary => renderSummaryText summary
  | .presentRich payload _ => renderPayloadText payload

private def resultToJson (_command : Command) (global : GlobalOptions) : CommandResult → Json
  | .status info =>
      Json.mkObj [
        ("command", toJson "status"),
        ("modules", namesJson global.modules),
        ("data", Json.mkObj [
          ("trackedDeclarations", toJson info.trackedDeclarations),
          ("trackedReferences", toJson info.trackedReferences),
          ("declarationsWithMultipleReferences", toJson info.declarationsWithMultipleReferences)
        ])
      ]
  | .decls entries =>
      Json.mkObj [
        ("command", toJson "decls"),
        ("modules", namesJson global.modules),
        ("data", Json.mkObj [
          ("entries", Json.arr <| entries.map declEntryJson)
        ])
      ]
  | .decl entry =>
      Json.mkObj [
        ("command", toJson "decl"),
        ("modules", namesJson global.modules),
        ("target", toJson entry.declName.toString),
        ("data", declEntryJson entry)
      ]
  | .refs entries =>
      Json.mkObj [
        ("command", toJson "refs"),
        ("modules", namesJson global.modules),
        ("data", Json.mkObj [
          ("entries", Json.arr <| entries.map refEntryJson)
        ])
      ]
  | .ref entry =>
      Json.mkObj [
        ("command", toJson "ref"),
        ("modules", namesJson global.modules),
        ("target", toJson (toString entry.ref)),
        ("data", refEntryJson entry)
      ]
  | .declDeps rows leaves =>
      Json.mkObj [
        ("command", toJson "deps"),
        ("modules", namesJson global.modules),
        ("mode", toJson "decl"),
        ("data", declDepsJson rows leaves)
      ]
  | .refDeps rows leaves =>
      Json.mkObj [
        ("command", toJson "deps"),
        ("modules", namesJson global.modules),
        ("mode", toJson "ref"),
        ("data", refDepsJson rows leaves)
      ]
  | .presentCompact summary =>
      Json.mkObj [
        ("command", toJson "present"),
        ("target", toJson (toString summary.ref)),
        ("mode", toJson "compact"),
        ("data", Json.mkObj [("summary", toJson summary)])
      ]
  | .presentRich payload bodyMode =>
      Json.mkObj [
        ("command", toJson "present"),
        ("target", toJson (toString payload.summary.ref)),
        ("mode", toJson "rich"),
        ("bodyMode", toJson (bodyModeName bodyMode)),
        ("data", toJson payload)
      ]

private def usageSection (usage : String) : List String :=
  ["Usage:", s!"  {usage}"]

private def titledSection (title : String) (lines : List String) : List String :=
  title :: lines

private def renderSections (sections : List (List String)) : String :=
  String.intercalate "\n\n" <| sections.map (String.intercalate "\n")

private def globalOptionsSection : List String :=
  titledSection "Global options:" [
    "  --module <Module.Name>  Import a module for tracked-state queries (repeatable)",
    "  --root <path>           Use a specific knowledge-base root",
    "  --format text|json      Output format for command results",
    "  --help                  Show this help text"
  ]

/-- Render help text for the informal CLI. -/
def renderHelp : HelpTopic → String
  | .informal =>
      renderSections [
        usageSection "lake exe aftk_cli informal [global-options] <command> ...",
        ["Query the AFTK informal layer."],
        globalOptionsSection,
        titledSection "Commands:" [
          "  status                Show high-level tracking counts",
          "  decls                 List tracked declarations",
          "  decl                  Show one tracked declaration",
          "  refs                  List tracked references",
          "  ref                   Show one tracked reference",
          "  deps                  Show declaration or reference dependency views",
          "  present               Render knowledge-base-backed presentation for one reference"
        ],
        ["Run `lake exe aftk_cli informal <command> --help` for detailed command help."]
      ]
  | .status =>
      renderSections [
        usageSection "lake exe aftk_cli informal status --module <Module.Name> [--module <Module.Name> ...]",
        ["Show high-level counts for tracked declarations and references."],
        globalOptionsSection
      ]
  | .decls =>
      renderSections [
        usageSection "lake exe aftk_cli informal decls --module <Module.Name> [options]",
        ["List tracked declarations and their referenced node ids."],
        titledSection "Options:" [
          "  --prefix <Decl.Name>    Restrict to a declaration prefix",
          "  --ref <NodeId>          Restrict to declarations referencing one node",
          "  --help                  Show this help text"
        ],
        globalOptionsSection
      ]
  | .decl =>
      renderSections [
        usageSection "lake exe aftk_cli informal decl <Decl.Name> --module <Module.Name> [--module <Module.Name> ...]",
        ["Show one tracked declaration and its referenced node ids."],
        globalOptionsSection
      ]
  | .refs =>
      renderSections [
        usageSection "lake exe aftk_cli informal refs --module <Module.Name> [options]",
        ["List tracked references and the declarations that reference them."],
        titledSection "Options:" [
          "  --prefix <NodeIdPrefix> Restrict to references under a dotted prefix",
          "  --help                  Show this help text"
        ],
        globalOptionsSection
      ]
  | .ref =>
      renderSections [
        usageSection "lake exe aftk_cli informal ref <NodeId> --module <Module.Name> [--module <Module.Name> ...]",
        ["Show one tracked reference and the declarations that reference it."],
        globalOptionsSection
      ]
  | .deps =>
      renderSections [
        usageSection "lake exe aftk_cli informal deps --module <Module.Name> [options]",
        ["Show derived declaration or reference dependency views."],
        titledSection "Options:" [
          "  --by decl|ref          Choose declaration or reference dependencies",
          "  --only-leaves          Restrict rows to empty-dependency leaves",
          "  --help                 Show this help text"
        ],
        globalOptionsSection
      ]
  | .present =>
      renderSections [
        usageSection "lake exe aftk_cli informal present <NodeId> [--root <path>] [options]",
        ["Render compact or rich knowledge-base-backed presentation for one node."],
        titledSection "Options:" [
          "  --mode compact|rich    Select compact or rich presentation (default: rich)",
          "  --body none|preview|full  Select body rendering policy for rich mode (default: preview)",
          "  --help                 Show this help text"
        ],
        globalOptionsSection
      ]

/-- Render a successful command result. -/
def renderSuccess (format : OutputFormat) (command : Command) (global : GlobalOptions) (result : CommandResult) : String :=
  match format with
  | .text => resultToText result
  | .json => Json.pretty (resultToJson command global result)

/-- Render a failure result in text or JSON form. -/
def renderFailure (format : OutputFormat) (command? : Option Command) (error : KnowledgeBaseError) : String :=
  match format with
  | .text =>
      let pref := command?.map (fun cmd => s!"{commandName cmd}: ") |>.getD ""
      s!"{pref}{error.code}: {error.message}"
  | .json =>
      Json.pretty <| Json.mkObj <|
        [ ("ok", toJson false)
        , ("error", Json.mkObj [
            ("code", toJson error.code),
            ("message", toJson error.message),
            ("exitCode", toJson error.exitCode.toNat)
          ])
        ] ++
        (match command? with
        | some cmd => [("command", toJson (commandName cmd))]
        | none => []) ++
        [ ("format", toJson (outputFormatName format)) ]

end Render
end Cli
end AFTK.Informal
