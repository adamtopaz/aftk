import AFTK.KnowledgeBase.Storage

namespace AFTK.KnowledgeBase

open Lean

namespace Search

inductive SearchScope
  | bodyText
  | title
  | summary
  | tags
  | metadata
  | allText
  deriving Repr, DecidableEq, Inhabited, BEq

instance : ToJson SearchScope where
  toJson
    | .bodyText => Json.str "bodyText"
    | .title => Json.str "title"
    | .summary => Json.str "summary"
    | .tags => Json.str "tags"
    | .metadata => Json.str "metadata"
    | .allText => Json.str "allText"

structure SearchHit where
  id : NodeId
  score? : Option Float := none
  title? : Option String := none
  summary? : Option String := none
  matchedScopes : Array SearchScope := #[]
  snippet? : Option String := none
  deriving Repr, Inhabited

instance : ToJson SearchHit where
  toJson hit :=
    Json.mkObj <|
      [ ("id", toJson hit.id) ] ++
      Json.opt "score" hit.score? ++
      Json.opt "title" hit.title? ++
      Json.opt "summary" hit.summary? ++
      (if hit.matchedScopes.isEmpty then [] else [("matchedScopes", toJson hit.matchedScopes)]) ++
      Json.opt "snippet" hit.snippet?

structure SearchResult where
  hits : Array SearchHit := #[]
  deriving Repr, Inhabited

instance : ToJson SearchResult where
  toJson result := Json.mkObj [("hits", toJson result.hits)]

structure IncomingRelationship where
  source : NodeId
  sourceTitle? : Option String := none
  relationship : Relationship
  deriving Repr, DecidableEq, Inhabited

instance : ToJson IncomingRelationship where
  toJson edge :=
    Json.mkObj <|
      [ ("source", toJson edge.source)
      , ("relationship", toJson edge.relationship)
      ] ++
      Json.opt "sourceTitle" edge.sourceTitle?

structure RelatedRelationships where
  id : NodeId
  outgoing : Array Relationship := #[]
  incoming : Array IncomingRelationship := #[]
  deriving Repr, DecidableEq, Inhabited

instance : ToJson RelatedRelationships where
  toJson rels := Json.mkObj [
    ("id", toJson rels.id),
    ("outgoing", toJson rels.outgoing),
    ("incoming", toJson rels.incoming)
  ]

private def containsCaseInsensitive (haystack needle : String) : Bool :=
  haystack.toLower.contains needle.toLower

private def truncateSnippet (text : String) (limit : Nat := 160) : String :=
  let text := text.trimAscii.toString
  if text.length <= limit then text else text.take limit |>.toString ++ "…"

private def applyLimit {α : Type} (items : Array α) (limit? : Option Nat) : Array α :=
  match limit? with
  | some limit => items.extract 0 (min limit items.size)
  | none => items

private def searchTextHit? (stored : StoredNode) (query : String) : Option SearchHit :=
  let metadata := stored.node.metadata
  let titleScopes := if containsCaseInsensitive metadata.title query then #[.title] else #[]
  let summaryScopes :=
    match metadata.summary? with
    | some summary => if containsCaseInsensitive summary query then #[.summary] else #[]
    | none => #[]
  let bodyScopes := if containsCaseInsensitive stored.node.body query then #[.bodyText] else #[]
  let matchedScopes := titleScopes ++ summaryScopes ++ bodyScopes
  if matchedScopes.isEmpty then
    none
  else
    let snippet? :=
      if matchedScopes.contains .bodyText then
        some (truncateSnippet stored.node.body)
      else
        metadata.summary?
    some {
      id := metadata.id
      title? := some metadata.title
      summary? := metadata.summary?
      matchedScopes := matchedScopes
      snippet? := snippet?
    }


def searchText
    (paths : KnowledgeBaseStoragePaths)
    (query : String)
    (limit? : Option Nat := none) : KBIO SearchResult := do
  let nodes ← Storage.loadAllStoredNodes paths
  let hits := nodes.toList.filterMap (fun node => searchTextHit? node query) |>.toArray
  return { hits := applyLimit hits limit? }


def searchTag
    (paths : KnowledgeBaseStoragePaths)
    (tag : String)
    (limit? : Option Nat := none) : KBIO SearchResult := do
  let nodes ← Storage.loadAllStoredNodes paths
  let hits :=
    nodes.toList.filterMap fun stored =>
      let metadata := stored.node.metadata
      if metadata.tags.contains tag then
        some {
          id := metadata.id
          title? := some metadata.title
          summary? := metadata.summary?
          matchedScopes := #[.tags]
        }
      else
        none
  return { hits := applyLimit hits.toArray limit? }


def outgoingRelationships (paths : KnowledgeBaseStoragePaths) (id : NodeId) : KBIO (Array Relationship) := do
  return (← Storage.loadStoredNode paths id).node.metadata.relationships


def incomingRelationships (paths : KnowledgeBaseStoragePaths) (id : NodeId) : KBIO (Array IncomingRelationship) := do
  let nodes ← Storage.loadAllStoredNodes paths
  let hits := nodes.foldl (init := #[]) fun acc stored =>
    let edges := stored.node.metadata.relationships.filter (fun rel => rel.target == id)
    acc ++ edges.map (fun rel => {
      source := stored.node.metadata.id
      sourceTitle? := some stored.node.metadata.title
      relationship := rel
    })
  return hits


def relatedRelationships (paths : KnowledgeBaseStoragePaths) (id : NodeId) : KBIO RelatedRelationships := do
  return {
    id := id
    outgoing := ← outgoingRelationships paths id
    incoming := ← incomingRelationships paths id
  }

end Search

end AFTK.KnowledgeBase
