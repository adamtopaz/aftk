module

public import AFTK.Informal

public section


namespace AFTK.Informal
namespace Cli

open Lean

inductive OutputFormat
  | text
  | json
  deriving Repr, DecidableEq, Inhabited

inductive DepsMode
  | decl
  | ref
  deriving Repr, DecidableEq, Inhabited

inductive PresentMode
  | compact
  | rich
  deriving Repr, DecidableEq, Inhabited

structure GlobalOptions where
  modules : Array Name := #[]
  root? : Option System.FilePath := none
  format : OutputFormat := .text
  deriving Repr, DecidableEq, Inhabited

structure DeclsOptions where
  prefix? : Option Name := none
  ref? : Option InformalReference := none
  deriving Repr, DecidableEq, Inhabited

structure RefsOptions where
  prefix? : Option String := none
  deriving Repr, DecidableEq, Inhabited

structure DepsOptions where
  mode : DepsMode := .decl
  onlyLeaves : Bool := false
  deriving Repr, DecidableEq, Inhabited

structure PresentOptions where
  mode : PresentMode := .rich
  bodyMode : BodyRenderMode := .preview
  deriving Repr, DecidableEq, Inhabited

inductive Command
  | status
  | decls (opts : DeclsOptions := {})
  | decl (declName : Name)
  | refs (opts : RefsOptions := {})
  | ref (ref : InformalReference)
  | deps (opts : DepsOptions := {})
  | present (ref : InformalReference) (opts : PresentOptions := {})
  deriving Repr, DecidableEq

inductive HelpTopic
  | informal
  | status
  | decls
  | decl
  | refs
  | ref
  | deps
  | present
  deriving Repr, DecidableEq, Inhabited

structure StatusResult where
  trackedDeclarations : Nat
  trackedReferences : Nat
  declarationsWithMultipleReferences : Nat
  deriving Repr, DecidableEq, Inhabited

inductive CommandResult
  | status (info : StatusResult)
  | decls (entries : Array InformalDeclEntry)
  | decl (entry : InformalDeclEntry)
  | refs (entries : Array InformalReferenceEntry)
  | ref (entry : InformalReferenceEntry)
  | declDeps (rows : Array InformalDeclDependencyEntry) (leaves : Array Name)
  | refDeps (rows : Array InformalReferenceDependencyEntry) (leaves : Array InformalReference)
  | presentCompact (summary : InformalPresentationSummary)
  | presentRich (payload : InformalPresentationPayload) (bodyMode : BodyRenderMode)
  deriving Repr

end Cli
end AFTK.Informal
