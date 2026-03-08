import AFTK
import AFTKTest.Informal.Assert
import Lean
import Lean.Elab.Import
import Lean.Elab.Frontend
import Lean.Elab.Command

namespace AFTKTest.Informal

open Lean
open AFTK.Informal
open AFTK.KnowledgeBase

private unsafe def importEnvironment (modules : Array Name) : IO Environment := do
  let sysroot ← Lean.findSysroot
  Lean.initSearchPath sysroot
  Lean.enableInitializersExecution
  let imports := modules.map fun moduleName => ({ module := moduleName : Import })
  Lean.importModules imports {} (loadExts := true)

initialize importedEnvCache : IO.Ref (Std.HashMap (Array Name) Environment) ← IO.mkRef {}

private unsafe def cachedEnvironment (modules : Array Name) : IO Environment := do
  let cache ← importedEnvCache.get
  match cache.get? modules with
  | some env =>
      pure env
  | none =>
      let env ← importEnvironment modules
      importedEnvCache.modify fun cache => cache.insert modules env
      pure env

private def runCoreInEnv (env : Environment) (x : CoreM α) : IO α := do
  let ctx : Core.Context := {
    fileName := "<aftk-informal-test>"
    fileMap := FileMap.ofString ""
    options := {}
  }
  let state : Core.State := { env := env }
  x.toIO' ctx state

@[inline] def basicRoot : TestM System.FilePath := do
  pure <| (← liftIO IO.currentDir) / "tests" / "informal" / "knowledgebase-fixtures" / "basic-valid"

@[inline] def longBodyRoot : TestM System.FilePath := do
  pure <| (← liftIO IO.currentDir) / "tests" / "informal" / "knowledgebase-fixtures" / "long-body"

@[inline] def malformedRoot : TestM System.FilePath := do
  pure <| (← liftIO IO.currentDir) / "tests" / "informal" / "knowledgebase-fixtures" / "malformed-node"

@[inline] def basicModules : Array Name :=
  #[`AFTKTest.Informal.Fixtures.Basic]

@[inline] def importsTopModules : Array Name :=
  #[`AFTKTest.Informal.Fixtures.Imports.Top]

@[inline] def cycleModules : Array Name :=
  #[`AFTKTest.Informal.Fixtures.Deps.Cycle]

@[inline] def directPlaceholderModules : Array Name :=
  #[`AFTKTest.Informal.Fixtures.DirectPlaceholder]

@[inline] unsafe def withImportedModules (modules : Array Name) (f : Environment → TestM α) : TestM α := do
  let env ← liftIO <| cachedEnvironment modules
  f env

@[inline] unsafe def runCoreInModules (modules : Array Name) (x : CoreM α) : TestM α := do
  let env ← liftIO <| cachedEnvironment modules
  liftIO <| runCoreInEnv env x

@[inline] def runTopLevelAftkCli (args : Array String) (input? : Option String := none) : TestM IO.Process.Output := do
  let cwd ← liftIO IO.currentDir
  liftIO <| IO.Process.output {
    cmd := "lake"
    args := #["exe", "aftk"] ++ args
    cwd := some cwd
  } input?

@[inline] def runInformalCli (args : Array String) (input? : Option String := none) : TestM IO.Process.Output :=
  runTopLevelAftkCli (#["informal"] ++ args) input?

@[inline] def runCompileFixture (path : System.FilePath) : TestM IO.Process.Output := do
  let cwd ← liftIO IO.currentDir
  liftIO <| IO.Process.output {
    cmd := "lake"
    args := #["env", "lean", path.toString]
    cwd := some cwd
  }

@[inline] def resolveRefAt (root : System.FilePath) (raw : String) : TestM ResolvedInformalReference := do
  let ref ←
    match informalReferenceOfString? raw with
    | .ok ref => pure ref
    | .error err => fail err
  let result ← liftIO <| (resolveInformalReferenceAtRoot root ref).toIO'
  match result with
  | .ok resolved => pure resolved
  | .error err => fail s!"{err.code}: {err.message}"

private partial def placeholderTagOfExpr? (expr : Expr) : Option Name := do
  match expr with
  | .lam _ _ body _ =>
      placeholderTagOfExpr? body
  | .letE _ _ _ body _ =>
      placeholderTagOfExpr? body
  | _ =>
      guard <| expr.getAppFn.constName? == some ``AFTK.Informal.Informal
      let args := expr.getAppArgs
      let tagExpr ← args[0]?
      tagExpr.name?

@[inline] def placeholderTagOfConstant? (env : Environment) (declName : Name) : Option Name := do
  let value ← (env.find? declName).bind (fun info => info.value? true)
  placeholderTagOfExpr? value

partial def collectHoverDocStrings : Lean.Elab.InfoTree → Array String
  | .context _ tree => collectHoverDocStrings tree
  | .node (.ofDelabTermInfo info) children =>
      let current := match info.docString? with | some doc => #[doc] | none => #[]
      children.foldl (init := current) fun acc child => acc ++ collectHoverDocStrings child
  | .node _ children =>
      children.foldl (init := #[]) fun acc child => acc ++ collectHoverDocStrings child
  | .hole _ => #[]

unsafe def collectDocStringsFromSource (input : String) (fileName : String := "<aftk-informal-info>") : IO (Array String) := do
  let inputCtx := Parser.mkInputContext input fileName
  let opts : Options := {}
  Lean.initSearchPath (← Lean.findSysroot)
  Lean.enableInitializersExecution
  let (header, parserState, messages) ← Parser.parseHeader inputCtx
  let (env, messages) ← Lean.Elab.processHeader header opts messages inputCtx
  let commandState := { Lean.Elab.Command.mkState env messages opts with infoState.enabled := true }
  let state ← Lean.Elab.IO.processCommands inputCtx parserState commandState
  pure <| state.commandState.infoState.trees.foldl (init := #[]) fun acc tree => acc ++ collectHoverDocStrings tree

end AFTKTest.Informal
