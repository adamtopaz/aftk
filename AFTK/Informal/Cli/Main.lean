module

public import AFTK.Informal.Cli.Parse
public import AFTK.Informal.Cli.Render
public import AFTK.Informal.Service

public section


namespace AFTK.Informal
namespace Cli
namespace Main

open Lean
open AFTK.KnowledgeBase

private def mapExcept (f : α → β) : Except ε α → Except ε β
  | .ok value => .ok (f value)
  | .error err => .error err

private def presentCommandResult (result : Service.PresentResult) : CommandResult :=
  match result.mode, result.payload?, result.bodyMode? with
  | .compact, _, _ =>
      .presentCompact result.summary
  | .rich, some payload, some bodyMode =>
      .presentRich payload bodyMode
  | .rich, _, _ =>
      .presentRich {
        summary := result.summary
      } .preview

private unsafe def commandResult (global : GlobalOptions) (command : Command) : IO (Except KnowledgeBaseError CommandResult) := do
  match command with
  | .status =>
      return mapExcept CommandResult.status (← Service.status global.modules)
  | .decls opts =>
      return mapExcept CommandResult.decls (← Service.decls global.modules { prefix? := opts.prefix?, ref? := opts.ref? })
  | .decl declName =>
      return mapExcept CommandResult.decl (← Service.decl global.modules declName)
  | .refs opts =>
      return mapExcept CommandResult.refs (← Service.refs global.modules { prefix? := opts.prefix? })
  | .ref ref =>
      return mapExcept CommandResult.ref (← Service.ref global.modules ref)
  | .deps opts =>
      match opts.mode with
      | .decl =>
          return mapExcept (fun result => CommandResult.declDeps result.rows result.leaves)
            (← Service.declDependencies global.modules opts.onlyLeaves)
      | .ref =>
          return mapExcept (fun result => CommandResult.refDeps result.rows result.leaves)
            (← Service.refDependencies global.modules opts.onlyLeaves)
  | .present ref opts => do
      let rootResult ← (Service.resolveRoot global.root?).toIO'
      match rootResult with
      | .error err =>
          return .error err
      | .ok root =>
          let result ← (Service.presentAtRoot root ref
            (match opts.mode with | .compact => .compact | .rich => .rich)
            opts.bodyMode).toIO'
          return mapExcept presentCommandResult result

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
