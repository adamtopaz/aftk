import Lean

namespace AFTK.Informal

open Lean

/-- Dedicated syntax category for knowledge-base-backed informal node ids. -/
declare_syntax_cat informalNodeId (behavior := symbol)

/--
V1 accepts an identifier-shaped payload and validates it semantically against
`AFTK.KnowledgeBase.NodeId` during elaboration.
-/
syntax ident : informalNodeId

syntax (name := informalTermWithRef) "informal[" informalNodeId "]" (ppSpace term:max)* : term

private def nodeIdAtomString? (stx : Syntax) : Option String :=
  if stx.isIdent then some stx.getId.toString else none

/-- Recover the raw dotted node-id text written inside `informal[...]`. -/
def informalNodeIdString? : Syntax → Option String
  | `(informalNodeId| $id:ident) => some id.getId.toString
  | stx => nodeIdAtomString? stx

end AFTK.Informal
