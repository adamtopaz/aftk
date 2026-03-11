module

public import AFTK.Informal.Dependencies
public import AFTK.Informal.Presentation

public section


namespace AFTK.Informal
namespace Service

open Lean
open AFTK.KnowledgeBase
open AFTK.KnowledgeBase.PathLayout

structure StatusInfo where
  trackedDeclarations : Nat
  trackedReferences : Nat
  declarationsWithMultipleReferences : Nat
  deriving Repr, DecidableEq, Inhabited, ToJson

structure DeclsOptions where
  prefix? : Option Name := none
  ref? : Option InformalReference := none
  deriving Repr, DecidableEq, Inhabited

structure RefsOptions where
  prefix? : Option String := none
  deriving Repr, DecidableEq, Inhabited

structure DeclDependenciesResult where
  rows : Array InformalDeclDependencyEntry := #[]
  leaves : Array Name := #[]
  deriving Repr, Inhabited

structure RefDependenciesResult where
  rows : Array InformalReferenceDependencyEntry := #[]
  leaves : Array InformalReference := #[]
  deriving Repr, Inhabited

structure PresentResult where
  mode : PresentationMode
  summary : InformalPresentationSummary
  payload? : Option InformalPresentationPayload := none
  bodyMode? : Option BodyRenderMode := none
  deriving Repr, Inhabited

instance : ToJson PresentResult where
  toJson result :=
    Json.mkObj <|
      [ ("mode", toJson result.mode)
      , ("summary", toJson result.summary)
      ] ++
      Json.opt "payload" result.payload? ++
      Json.opt "bodyMode" result.bodyMode?

private def liftIOKB {α : Type} (action : IO α) : KBIO α :=
  action.toEIO fun err => KnowledgeBaseError.generic "io.error" err.toString 1


def resolveRoot (root? : Option System.FilePath := none) : KBIO System.FilePath :=
  liftIOKB <| PathLayout.resolveRootPath root?


def parseDottedName (kind raw : String) : Except KnowledgeBaseError Name := do
  let trimmed := raw.trimAscii.toString
  if trimmed.isEmpty then
    throw <| KnowledgeBaseError.usage s!"{kind} name must be non-empty"
  let parts := trimmed.splitOn "."
  if parts.any String.isEmpty then
    throw <| KnowledgeBaseError.usage s!"Invalid {kind} name '{raw}'"
  pure <| parts.foldl (init := Name.anonymous) Name.str


def parseDeclName (raw : String) : Except KnowledgeBaseError Name :=
  parseDottedName "declaration" raw


def parseModuleNames (modules : Array String) : Except KnowledgeBaseError (Array Name) := do
  modules.mapM (parseDottedName "module")

private unsafe def importEnvironment (modules : Array Name) : IO Environment := do
  let sysroot ← Lean.findSysroot
  Lean.initSearchPath sysroot
  Lean.enableInitializersExecution
  let imports := modules.map fun moduleName => ({ module := moduleName : Import })
  Lean.importModules imports {} (loadExts := true)

private def runCoreInEnv (env : Environment) (x : CoreM α) : IO α := do
  let ctx : Core.Context := {
    fileName := "<aftk-informal-service>"
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

private def statusInfoInEnv : CoreM StatusInfo := do
  let declEntries ← allInformalDeclEntries
  let refEntries ← allInformalReferenceEntries
  pure {
    trackedDeclarations := declEntries.size
    trackedReferences := refEntries.size
    declarationsWithMultipleReferences := declEntries.foldl (init := 0) fun acc entry =>
      if entry.refs.size > 1 then acc + 1 else acc
  }

private def declEntryInEnv (declName : Name) : CoreM (Except KnowledgeBaseError InformalDeclEntry) := do
  match ← informalDeclEntry? declName with
  | some entry => pure <| .ok entry
  | none => pure <| .error <| KnowledgeBaseError.notFound "informal.notTracked" s!"declaration '{declName}' is not tracked"

private def refEntryInEnv (ref : InformalReference) : CoreM (Except KnowledgeBaseError InformalReferenceEntry) := do
  match ← informalReferenceEntry? ref with
  | some entry => pure <| .ok entry
  | none => pure <| .error <| KnowledgeBaseError.notFound "informal.notTracked" s!"reference '{ref}' is not tracked"

private def declDependenciesInEnv (onlyLeaves : Bool) : CoreM DeclDependenciesResult := do
  let rows ← allInformalDeclDependencyEntries
  let leaves ← informalDeclDependencyLeaves
  let rows := if onlyLeaves then rows.filter (·.dependencies.isEmpty) else rows
  pure { rows, leaves }

private def refDependenciesInEnv (onlyLeaves : Bool) : CoreM RefDependenciesResult := do
  let rows ← allInformalReferenceDependencyEntries
  let leaves ← informalReferenceDependencyLeaves
  let rows := if onlyLeaves then rows.filter (·.dependencies.isEmpty) else rows
  pure { rows, leaves }

private unsafe def runImportedQuery (modules : Array Name) (query : CoreM α) : IO (Except KnowledgeBaseError α) := do
  try
    let env ← importEnvironment modules
    let result ← runCoreInEnv env query
    pure <| .ok result
  catch ex =>
    pure <| .error <| KnowledgeBaseError.generic "informal.queryFailed" ex.toString 1

private unsafe def runImportedCheckedQuery
    (modules : Array Name)
    (query : CoreM (Except KnowledgeBaseError α)) : IO (Except KnowledgeBaseError α) := do
  match ← runImportedQuery modules query with
  | .ok (.ok result) => pure <| .ok result
  | .ok (.error err) => pure <| .error err
  | .error err => pure <| .error err

unsafe def status (modules : Array Name) : IO (Except KnowledgeBaseError StatusInfo) :=
  runImportedQuery modules statusInfoInEnv

unsafe def decls
    (modules : Array Name)
    (opts : DeclsOptions := {}) : IO (Except KnowledgeBaseError (Array InformalDeclEntry)) :=
  runImportedQuery modules do
    let entries ← allInformalDeclEntries
    pure <| filterDeclEntries entries opts

unsafe def decl
    (modules : Array Name)
    (declName : Name) : IO (Except KnowledgeBaseError InformalDeclEntry) :=
  runImportedCheckedQuery modules (declEntryInEnv declName)

unsafe def refs
    (modules : Array Name)
    (opts : RefsOptions := {}) : IO (Except KnowledgeBaseError (Array InformalReferenceEntry)) :=
  runImportedQuery modules do
    let entries ← allInformalReferenceEntries
    pure <| filterRefEntries entries opts

unsafe def ref
    (modules : Array Name)
    (target : InformalReference) : IO (Except KnowledgeBaseError InformalReferenceEntry) :=
  runImportedCheckedQuery modules (refEntryInEnv target)

unsafe def declDependencies
    (modules : Array Name)
    (onlyLeaves : Bool := false) : IO (Except KnowledgeBaseError DeclDependenciesResult) :=
  runImportedQuery modules (declDependenciesInEnv onlyLeaves)

unsafe def refDependencies
    (modules : Array Name)
    (onlyLeaves : Bool := false) : IO (Except KnowledgeBaseError RefDependenciesResult) :=
  runImportedQuery modules (refDependenciesInEnv onlyLeaves)


def presentAtRoot
    (root : System.FilePath)
    (ref : InformalReference)
    (mode : PresentationMode := .rich)
    (bodyMode : BodyRenderMode := .preview) : KBIO PresentResult := do
  let resolved ← resolveInformalReferenceAtRoot root ref
  let summary := summaryOfResolved resolved
  match mode with
  | .compact =>
      pure {
        mode := .compact
        summary := summary
      }
  | .rich =>
      pure {
        mode := .rich
        summary := summary
        payload? := some <| payloadOfResolved resolved bodyMode
        bodyMode? := some bodyMode
      }


def present
    (ref : InformalReference)
    (mode : PresentationMode := .rich)
    (bodyMode : BodyRenderMode := .preview)
    (root? : Option System.FilePath := none) : KBIO PresentResult := do
  presentAtRoot (← resolveRoot root?) ref mode bodyMode

end Service
end AFTK.Informal
