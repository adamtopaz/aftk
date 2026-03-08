module

public import AFTK.Informal.Cli.Types

public section


namespace AFTK.Informal
namespace Cli
namespace Parse

open Lean
open AFTK.KnowledgeBase

private def usageError {α : Type} (message : String) : Except KnowledgeBaseError α :=
  throw <| KnowledgeBaseError.usage message

private def parseDottedName (kind raw : String) : Except KnowledgeBaseError Name := do
  let trimmed := raw.trimAscii.toString
  if trimmed.isEmpty then
    usageError s!"{kind} name must be non-empty"
  let parts := trimmed.splitOn "."
  if parts.any String.isEmpty then
    usageError s!"Invalid {kind} name '{raw}'"
  pure <| parts.foldl (init := Name.anonymous) Name.str

private def parseInformalReference (raw : String) : Except KnowledgeBaseError InformalReference :=
  match informalReferenceOfString? raw with
  | .ok ref => pure ref
  | .error err => usageError s!"Invalid node id '{raw}': {err}"

private def parseOutputFormat (raw : String) : Except KnowledgeBaseError OutputFormat :=
  match raw with
  | "text" => pure .text
  | "json" => pure .json
  | _ => usageError s!"Unknown output format '{raw}'; expected text or json"

private def parseDepsMode (raw : String) : Except KnowledgeBaseError DepsMode :=
  match raw with
  | "decl" => pure .decl
  | "ref" => pure .ref
  | _ => usageError s!"Unknown dependency mode '{raw}'; expected decl or ref"

private def parsePresentMode (raw : String) : Except KnowledgeBaseError PresentMode :=
  match raw with
  | "compact" => pure .compact
  | "rich" => pure .rich
  | _ => usageError s!"Unknown present mode '{raw}'; expected compact or rich"

private def parseBodyRenderMode (raw : String) : Except KnowledgeBaseError BodyRenderMode :=
  match raw with
  | "none" => pure .none
  | "preview" => pure .preview
  | "full" => pure .full
  | _ => usageError s!"Unknown body mode '{raw}'; expected none, preview, or full"

private def isHelpFlag (arg : String) : Bool :=
  arg == "--help" || arg == "-h"

private partial def stripLeadingGlobalOptions : List String → Except KnowledgeBaseError (List String)
  | "--module" :: _module :: rest => stripLeadingGlobalOptions rest
  | "--module" :: [] => usageError "Missing value for --module"
  | "--root" :: _path :: rest => stripLeadingGlobalOptions rest
  | "--root" :: [] => usageError "Missing value for --root"
  | "--format" :: format :: rest => do
      let _ ← parseOutputFormat format
      stripLeadingGlobalOptions rest
  | "--format" :: [] => usageError "Missing value for --format"
  | arg :: rest =>
      if isHelpFlag arg then
        pure (arg :: rest)
      else if arg.startsWith "--" then
        pure (arg :: rest)
      else
        pure (arg :: rest)
  | [] => pure []

private def helpTopicOfCommand? : String → Option HelpTopic
  | "status" => some .status
  | "decls" => some .decls
  | "decl" => some .decl
  | "refs" => some .refs
  | "ref" => some .ref
  | "deps" => some .deps
  | "present" => some .present
  | _ => none

/-- Return the requested help topic, if any. -/
def parseHelpTopic? (args : List String) : Except KnowledgeBaseError (Option HelpTopic) := do
  let rest ← stripLeadingGlobalOptions args
  if rest.any isHelpFlag then
    match rest.find? (fun arg => !(arg.startsWith "--") && !isHelpFlag arg) with
    | some cmd => pure <| some ((helpTopicOfCommand? cmd).getD HelpTopic.informal)
    | none => pure <| some HelpTopic.informal
  else
    pure none

private inductive CommandBuilder where
  | status
  | decls (opts : DeclsOptions)
  | decl (target? : Option Name)
  | refs (opts : RefsOptions)
  | ref (target? : Option InformalReference)
  | deps (opts : DepsOptions)
  | present (target? : Option InformalReference) (opts : PresentOptions)

private structure ParseState where
  global : GlobalOptions := {}
  command? : Option CommandBuilder := none

private def setCommand (state : ParseState) (command : CommandBuilder) : Except KnowledgeBaseError ParseState :=
  match state.command? with
  | some _ => usageError "Only one informal command may be specified"
  | none => pure { state with command? := some command }

private def parseCommandName (state : ParseState) (raw : String) : Except KnowledgeBaseError ParseState :=
  match raw with
  | "status" => setCommand state .status
  | "decls" => setCommand state (.decls {})
  | "decl" => setCommand state (.decl none)
  | "refs" => setCommand state (.refs {})
  | "ref" => setCommand state (.ref none)
  | "deps" => setCommand state (.deps {})
  | "present" => setCommand state (.present none {})
  | _ => usageError s!"Unknown informal command '{raw}'"

private def updateCommand (state : ParseState) (builder : CommandBuilder) : ParseState :=
  { state with command? := some builder }

private def parsePositional (state : ParseState) (raw : String) : Except KnowledgeBaseError ParseState := do
  match state.command? with
  | none => parseCommandName state raw
  | some (.decl none) => pure <| updateCommand state (.decl (some (← parseDottedName "declaration" raw)))
  | some (.ref none) => pure <| updateCommand state (.ref (some (← parseInformalReference raw)))
  | some (.present none opts) => pure <| updateCommand state (.present (some (← parseInformalReference raw)) opts)
  | some (.status) => usageError s!"Unexpected positional argument '{raw}' for status"
  | some (.decls _) => usageError s!"Unexpected positional argument '{raw}' for decls"
  | some (.decl (some _)) => usageError s!"Unexpected extra declaration argument '{raw}'"
  | some (.refs _) => usageError s!"Unexpected positional argument '{raw}' for refs"
  | some (.ref (some _)) => usageError s!"Unexpected extra reference argument '{raw}'"
  | some (.deps _) => usageError s!"Unexpected positional argument '{raw}' for deps"
  | some (.present (some _) _) => usageError s!"Unexpected extra reference argument '{raw}' for present"

private def ensureModulesIfNeeded (global : GlobalOptions) (command : Command) : Except KnowledgeBaseError Unit :=
  match command with
  | .present _ _ => pure ()
  | _ =>
      if global.modules.isEmpty then
        usageError "missing required option '--module <Module.Name>'"
      else
        pure ()

private def finalizeCommand (state : ParseState) : Except KnowledgeBaseError (GlobalOptions × Command) := do
  let some builder := state.command?
    | usageError "Expected an informal command"
  let command ← match builder with
    | .status => pure Command.status
    | .decls opts => pure <| .decls opts
    | .decl (some declName) => pure <| .decl declName
    | .decl none => usageError "decl requires <Decl.Name>"
    | .refs opts => pure <| .refs opts
    | .ref (some ref) => pure <| .ref ref
    | .ref none => usageError "ref requires <NodeId>"
    | .deps opts => pure <| .deps opts
    | .present (some ref) opts => pure <| .present ref opts
    | .present none _ => usageError "present requires <NodeId>"
  ensureModulesIfNeeded state.global command
  pure (state.global, command)

private partial def parseArgsAux : ParseState → List String → Except KnowledgeBaseError (GlobalOptions × Command)
  | state, [] => finalizeCommand state
  | state, "--module" :: moduleRaw :: rest => do
      let moduleName ← parseDottedName "module" moduleRaw
      parseArgsAux { state with global.modules := state.global.modules.push moduleName } rest
  | _, "--module" :: [] => usageError "Missing value for --module"
  | state, "--root" :: path :: rest =>
      parseArgsAux { state with global.root? := some path } rest
  | _, "--root" :: [] => usageError "Missing value for --root"
  | state, "--format" :: formatRaw :: rest => do
      let format ← parseOutputFormat formatRaw
      parseArgsAux { state with global.format := format } rest
  | _, "--format" :: [] => usageError "Missing value for --format"
  | state, "--prefix" :: prefRaw :: rest => do
      match state.command? with
      | some (.decls opts) =>
          let pref ← parseDottedName "declaration prefix" prefRaw
          parseArgsAux (updateCommand state (.decls { opts with prefix? := some pref })) rest
      | some (.refs opts) =>
          parseArgsAux (updateCommand state (.refs { opts with prefix? := some prefRaw })) rest
      | _ =>
          usageError "--prefix is only valid for decls and refs"
  | _, "--prefix" :: [] => usageError "Missing value for --prefix"
  | state, "--ref" :: refRaw :: rest => do
      match state.command? with
      | some (.decls opts) =>
          let ref ← parseInformalReference refRaw
          parseArgsAux (updateCommand state (.decls { opts with ref? := some ref })) rest
      | _ =>
          usageError "--ref is only valid for decls"
  | _, "--ref" :: [] => usageError "Missing value for --ref"
  | state, "--by" :: modeRaw :: rest => do
      match state.command? with
      | some (.deps opts) =>
          let mode ← parseDepsMode modeRaw
          parseArgsAux (updateCommand state (.deps { opts with mode := mode })) rest
      | _ =>
          usageError "--by is only valid for deps"
  | _, "--by" :: [] => usageError "Missing value for --by"
  | state, "--only-leaves" :: rest => do
      match state.command? with
      | some (.deps opts) =>
          parseArgsAux (updateCommand state (.deps { opts with onlyLeaves := true })) rest
      | _ =>
          usageError "--only-leaves is only valid for deps"
  | state, "--mode" :: modeRaw :: rest => do
      match state.command? with
      | some (.present target? opts) =>
          let mode ← parsePresentMode modeRaw
          parseArgsAux (updateCommand state (.present target? { opts with mode := mode })) rest
      | _ =>
          usageError "--mode is only valid for present"
  | _, "--mode" :: [] => usageError "Missing value for --mode"
  | state, "--body" :: bodyRaw :: rest => do
      match state.command? with
      | some (.present target? opts) =>
          let bodyMode ← parseBodyRenderMode bodyRaw
          parseArgsAux (updateCommand state (.present target? { opts with bodyMode := bodyMode })) rest
      | _ =>
          usageError "--body is only valid for present"
  | _, "--body" :: [] => usageError "Missing value for --body"
  | state, arg :: rest => do
      if isHelpFlag arg then
        usageError "Help flags should be handled before parseArgs"
      else if arg.startsWith "--" then
        usageError s!"Unknown option '{arg}'"
      else
        let state ← parsePositional state arg
        parseArgsAux state rest

/-- Parse CLI arguments after help handling. -/
def parseArgs (args : List String) : Except KnowledgeBaseError (GlobalOptions × Command) :=
  parseArgsAux {} args

end Parse
end Cli
end AFTK.Informal
