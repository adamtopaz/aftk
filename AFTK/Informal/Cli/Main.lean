module

public import AFTK.Informal.Cli.Parse
public import AFTK.Informal.Cli.Render
public import AFTK.KnowledgeBase.PathLayout

public section


namespace AFTK.Informal
namespace Cli
namespace Main

open Lean
open AFTK.KnowledgeBase
open AFTK.KnowledgeBase.PathLayout

private unsafe def importEnvironment (modules : Array Name) : IO Environment := do
  let sysroot ← Lean.findSysroot
  Lean.initSearchPath sysroot
  Lean.enableInitializersExecution
  let imports := modules.map fun moduleName => ({ module := moduleName : Import })
  Lean.importModules imports {} (loadExts := true)

private def runCoreInEnv (env : Environment) (x : CoreM α) : IO α := do
  let ctx : Core.Context := {
    fileName := "<aftk-informal-cli>"
    fileMap := FileMap.ofString ""
    options := {}
  }
  let state : Core.State := { env := env }
  x.toIO' ctx state

private def declMatchesPrefix (pref : Name) (declName : Name) : Bool :=
  pref.isPrefixOf declName

private def filterDeclEntries (entries : Array InformalDeclEntry) (opts : DeclsOptions) : Array InformalDeclEntry :=
  entries.filter fun entry =>
    let prefixOk := match opts.prefix? with
      | some pref => declMatchesPrefix pref entry.declName
      | none => true
    let refOk := match opts.ref? with
      | some ref => entry.refs.contains ref
      | none => true
    prefixOk && refOk

private def filterRefEntries (entries : Array InformalReferenceEntry) (opts : RefsOptions) : Array InformalReferenceEntry :=
  entries.filter fun entry =>
    match opts.prefix? with
    | some pref => entry.ref.startsWithSegmentPrefix pref
    | none => true

private def statusInfo : CoreM StatusResult := do
  let declEntries ← allInformalDeclEntries
  let refEntries ← allInformalReferenceEntries
  pure {
    trackedDeclarations := declEntries.size
    trackedReferences := refEntries.size
    declarationsWithMultipleReferences := declEntries.foldl (init := 0) fun acc entry =>
      if entry.refs.size > 1 then acc + 1 else acc
  }

private def commandResultInEnv (command : Command) : CoreM CommandResult := do
  match command with
  | .status =>
      .status <$> statusInfo
  | .decls opts => do
      let entries ← allInformalDeclEntries
      pure <| .decls (filterDeclEntries entries opts)
  | .decl declName => do
      let some entry ← informalDeclEntry? declName
        | throwError "declaration '{declName}' is not tracked"
      pure <| .decl entry
  | .refs opts => do
      let entries ← allInformalReferenceEntries
      pure <| .refs (filterRefEntries entries opts)
  | .ref ref => do
      let some entry ← informalReferenceEntry? ref
        | throwError "reference '{ref}' is not tracked"
      pure <| .ref entry
  | .deps opts =>
      match opts.mode with
      | .decl =>
          let rows ← allInformalDeclDependencyEntries
          let leaves ← informalDeclDependencyLeaves
          let rows := if opts.onlyLeaves then rows.filter (·.dependencies.isEmpty) else rows
          pure <| .declDeps rows leaves
      | .ref =>
          let rows ← allInformalReferenceDependencyEntries
          let leaves ← informalReferenceDependencyLeaves
          let rows := if opts.onlyLeaves then rows.filter (·.dependencies.isEmpty) else rows
          pure <| .refDeps rows leaves
  | .present .. =>
      throwError "present is not an environment-backed command"

private def presentResult (global : GlobalOptions) (ref : InformalReference) (opts : PresentOptions) : IO (Except KnowledgeBaseError CommandResult) := do
  let root ← resolveRootPath global.root?
  let resolved ← (resolveInformalReferenceAtRoot root ref).toIO'
  pure <| resolved.map fun resolved =>
    match opts.mode with
    | .compact => .presentCompact (summaryOfResolved resolved)
    | .rich => .presentRich (payloadOfResolved resolved opts.bodyMode) opts.bodyMode

private unsafe def commandResult (global : GlobalOptions) (command : Command) : IO (Except KnowledgeBaseError CommandResult) := do
  match command with
  | .present ref opts =>
      presentResult global ref opts
  | _ =>
      try
        let env ← importEnvironment global.modules
        let result ← runCoreInEnv env (commandResultInEnv command)
        pure <| .ok result
      catch ex =>
        let message := ex.toString
        if message.contains "is not tracked" then
          pure <| .error <| KnowledgeBaseError.notFound "informal.notTracked" message
        else
          pure <| .error <| KnowledgeBaseError.generic "informal.queryFailed" message 1

/-- Run the informal CLI and return its exit code. -/
unsafe def run (args : List String) : IO UInt8 := do
  match Parse.parseHelpTopic? args with
  | .error err =>
      IO.eprintln <| Render.renderFailure .text none err
      pure err.exitCode
  | .ok (some topic) =>
      IO.println <| Render.renderHelp topic
      pure 0
  | .ok none =>
      match Parse.parseArgs args with
      | .error err =>
          IO.eprintln <| Render.renderFailure .text none err
          pure err.exitCode
      | .ok (global, command) =>
          match ← commandResult global command with
          | .ok result =>
              IO.println <| Render.renderSuccess global.format command global result
              pure 0
          | .error err =>
              match global.format with
              | .text => IO.eprintln <| Render.renderFailure .text (some command) err
              | .json => IO.println <| Render.renderFailure .json (some command) err
              pure err.exitCode

/-- `lake exe aftk informal ...` entrypoint. -/
unsafe def main (args : List String) : IO Unit := do
  IO.Process.exit (← run args)

end Main
end Cli
end AFTK.Informal
