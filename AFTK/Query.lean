module

public import AFTK.Store

public section

namespace AFTK

structure KbQuery where
  idPrefix : Option String := none
  kind : Option KnowledgeKind := none
  basis : Option KnowledgeBasis := none
  tag : Option String := none
  source : Option SourceId := none
  packet : Option PacketId := none
  location : Option Informalize.LocationId := none
  relatedTo : Option KnowledgeId := none
  text : Option String := none
  limit : Option Nat := none
  deriving Inhabited, Repr

private def matchesText (entry : KnowledgeEntry) (body : String) (text : String) : Bool :=
  containsCaseInsensitive entry.id.raw text ||
  containsCaseInsensitive entry.title text ||
  ((entry.summary?.map fun summary => containsCaseInsensitive summary text).getD false) ||
  containsCaseInsensitive body text

private def matchesIdPrefix (query : KbQuery) (entry : KnowledgeEntry) : Bool :=
  match query.idPrefix with
  | some value => entry.id.raw.startsWith value
  | none => true

private def matchesKind (query : KbQuery) (entry : KnowledgeEntry) : Bool :=
  match query.kind with
  | some value => value == entry.kind
  | none => true

private def matchesBasis (query : KbQuery) (entry : KnowledgeEntry) : Bool :=
  match query.basis with
  | some value => value == entry.basis
  | none => true

private def matchesTag (query : KbQuery) (entry : KnowledgeEntry) : Bool :=
  match query.tag with
  | some value => entry.tags.contains value
  | none => true

private def matchesSource (query : KbQuery) (entry : KnowledgeEntry) : Bool :=
  match query.source with
  | some value =>
    entry.sourceRefs.contains value ||
      entry.provenance.any (fun prov => prov.targetKind == .source && prov.targetId == value.raw)
  | none => true

private def matchesPacket (query : KbQuery) (entry : KnowledgeEntry) : Bool :=
  match query.packet with
  | some value =>
    entry.packetRefs.contains value ||
      entry.provenance.any (fun prov => prov.targetKind == .packet && prov.targetId == value.raw)
  | none => true

private def matchesLocation (query : KbQuery) (entry : KnowledgeEntry) : Bool :=
  match query.location with
  | some value =>
    entry.scaffoldRefs.contains value ||
      entry.provenance.any (fun prov => prov.targetKind == .scaffold && prov.targetId == toString value)
  | none => true

private def matchesRelatedTo (query : KbQuery) (entry : KnowledgeEntry) : Bool :=
  match query.relatedTo with
  | some value => entry.links.any (fun link => link.target == value)
  | none => true

private def matchesTextQuery (query : KbQuery) (entry : KnowledgeEntry) (body : String) : Bool :=
  match query.text with
  | some value => matchesText entry body value
  | none => true

private def matchesQuery
    (query : KbQuery)
    (entry : KnowledgeEntry)
    (body : String) : Bool :=
  matchesIdPrefix query entry &&
  matchesKind query entry &&
  matchesBasis query entry &&
  matchesTag query entry &&
  matchesSource query entry &&
  matchesPacket query entry &&
  matchesLocation query entry &&
  matchesRelatedTo query entry &&
  matchesTextQuery query entry body

/-- Query knowledge entries using deterministic filtering and id ordering. -/
def queryKnowledge
    (data : LoadedStoreData)
    (query : KbQuery) : IO (Except String (Array (KnowledgeEntry × String))) := do
  let ordered := data.knowledge.qsort (fun a b => a.id.raw < b.id.raw)
  let mut results : Array (KnowledgeEntry × String) := #[]
  for entry in ordered do
    match ← readKnowledgeBody data.store.root entry.id with
    | .error err =>
      return .error err
    | .ok body =>
      if matchesQuery query entry body then
        results := results.push (entry, body)
  match query.limit with
  | some limit =>
    return .ok (results.extract 0 (min limit results.size))
  | none =>
    return .ok results

end AFTK
