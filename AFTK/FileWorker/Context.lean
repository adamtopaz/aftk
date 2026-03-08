module

public import Lean
public import Lean.Server.InfoUtils

public section


namespace AFTK.FileWorker.Context

open Lean Parser Elab

structure CommandTree where
  stx : Syntax
  infoTree : InfoTree
  range? : Option Syntax.Range
  deriving Inhabited

structure WorkerContext where
  path : System.FilePath
  inputCtx : Parser.InputContext
  env : Environment
  infoTrees : PersistentArray InfoTree
  commandTrees : Array CommandTree

partial def rootCommandStx? : InfoTree → Option Syntax
  | .context _ tree =>
      rootCommandStx? tree
  | .node (.ofCommandInfo info) _ =>
      some info.stx
  | .node _ children =>
      children.toArray.findSome? rootCommandStx?
  | .hole _ =>
      none

unsafe def build (path : System.FilePath) (opts : Options := {}) : IO WorkerContext := do
  let input ← IO.FS.readFile path
  let inputCtx := Parser.mkInputContext input path.toString
  Lean.initSearchPath (← Lean.findSysroot)
  Lean.enableInitializersExecution
  let (header, parserState, messages) ← Parser.parseHeader inputCtx
  let (env, messages) ← Elab.processHeader header opts messages inputCtx
  let commandState := { Elab.Command.mkState env messages opts with infoState.enabled := true }
  let state ← Elab.IO.processCommands inputCtx parserState commandState
  let infoTrees := state.commandState.infoState.trees
  let commandTrees := infoTrees.toArray.filterMap fun infoTree => do
    let stx ← rootCommandStx? infoTree
    some {
      stx := stx
      infoTree := infoTree
      range? := stx.getRangeWithTrailing? (canonicalOnly := true)
    }
  pure {
    path := path
    inputCtx := inputCtx
    env := state.commandState.env
    infoTrees := infoTrees
    commandTrees := commandTrees
  }

end AFTK.FileWorker.Context
