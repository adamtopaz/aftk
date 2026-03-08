module

public import AFTK.KnowledgeBase

public section


namespace AFTK.Informal

open Lean
open System
open AFTK.KnowledgeBase

structure InformalReference where
  nodeId : NodeId
  deriving Repr, DecidableEq, Inhabited, BEq, Hashable

instance : ToString InformalReference where
  toString ref := ref.nodeId.value

instance : Ord InformalReference where
  compare a b := compare a.nodeId b.nodeId

instance : ToJson InformalReference where
  toJson ref := toJson ref.nodeId

instance : FromJson InformalReference where
  fromJson? json := do
    let nodeId ← fromJson? (α := NodeId) json
    pure { nodeId }

namespace InformalReference

def ofNodeId (nodeId : NodeId) : InformalReference :=
  { nodeId }


def ofString? (raw : String) : Except String InformalReference := do
  let nodeId ← NodeId.ofString? raw
  pure { nodeId }


def render (ref : InformalReference) : String :=
  ref.nodeId.value


def startsWithSegmentPrefix (ref : InformalReference) (pref : String) : Bool :=
  NodeId.startsWithSegmentPrefix ref.nodeId pref

end InformalReference

structure ResolvedInformalReference where
  ref : InformalReference
  storedNode : StoredNode
  deriving Repr, DecidableEq

namespace ResolvedInformalReference

@[inline] def nodeId (resolved : ResolvedInformalReference) : NodeId :=
  resolved.ref.nodeId

@[inline] def metadata (resolved : ResolvedInformalReference) : NodeMetadata :=
  resolved.storedNode.node.metadata

@[inline] def body (resolved : ResolvedInformalReference) : String :=
  resolved.storedNode.node.body

end ResolvedInformalReference

private def liftIOKB {α : Type} (action : IO α) : KBIO α :=
  action.toEIO fun err => KnowledgeBaseError.generic "io.error" err.toString 1

/-- Validate a raw bracket payload as an informal reference. -/
def informalReferenceOfString? (raw : String) : Except String InformalReference :=
  InformalReference.ofString? raw

/-- Resolve an informal reference using an already initialized knowledge-base root. -/
def resolveInformalReferenceIn
    (paths : KnowledgeBaseStoragePaths)
    (ref : InformalReference) : KBIO ResolvedInformalReference := do
  let storedNode ← Storage.loadStoredNode paths ref.nodeId
  pure { ref, storedNode }

/-- Resolve an informal reference against an explicit knowledge-base root path. -/
def resolveInformalReferenceAtRoot
    (root : FilePath)
    (ref : InformalReference) : KBIO ResolvedInformalReference := do
  let resolvedRoot ← liftIOKB <| PathLayout.resolveRootPath (some root)
  let (paths, _) ← Storage.resolveInitializedRoot resolvedRoot
  resolveInformalReferenceIn paths ref

/-- Resolve an informal reference using the default knowledge-base root policy. -/
def resolveInformalReference
    (ref : InformalReference)
    (root? : Option FilePath := none) : KBIO ResolvedInformalReference := do
  let resolvedRoot ← liftIOKB <| PathLayout.resolveRootPath root?
  let (paths, _) ← Storage.resolveInitializedRoot resolvedRoot
  resolveInformalReferenceIn paths ref

end AFTK.Informal
