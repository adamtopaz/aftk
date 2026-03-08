import AFTK.Informal.References

namespace AFTK.Informal

open Lean
open AFTK.KnowledgeBase

structure InformalPresentationSummary where
  ref : InformalReference
  title : String
  kind? : Option NodeKind := none
  status? : Option NodeStatus := none
  summary? : Option String := none
  deriving Repr, Inhabited, DecidableEq

inductive InformalBodyPresentation
  | none
  | preview (text : String) (truncated : Bool)
  | full (text : String)
  deriving Repr, Inhabited, DecidableEq

structure InformalPresentationPayload where
  summary : InformalPresentationSummary
  tags : Array String := #[]
  authors : Array String := #[]
  relationshipLines : Array String := #[]
  leanRefLines : Array String := #[]
  body : InformalBodyPresentation := .none
  deriving Repr, Inhabited, DecidableEq

inductive PresentationMode
  | compact
  | rich
  deriving Repr, Inhabited, DecidableEq

inductive BodyRenderMode
  | none
  | preview
  | full
  deriving Repr, Inhabited, DecidableEq

instance : ToJson InformalPresentationSummary where
  toJson summary :=
    Json.mkObj <|
      [ ("ref", toJson summary.ref)
      , ("title", toJson summary.title)
      ] ++
      Json.opt "kind" summary.kind? ++
      Json.opt "status" summary.status? ++
      Json.opt "summary" summary.summary?

instance : ToJson InformalBodyPresentation where
  toJson
    | .none => Json.mkObj [("kind", toJson "none")]
    | .preview text truncated => Json.mkObj [
        ("kind", toJson "preview"),
        ("truncated", toJson truncated),
        ("text", toJson text)
      ]
    | .full text => Json.mkObj [
        ("kind", toJson "full"),
        ("text", toJson text)
      ]

instance : ToJson InformalPresentationPayload where
  toJson payload :=
    Json.mkObj <|
      [ ("summary", toJson payload.summary)
      , ("body", toJson payload.body)
      ] ++
      (if payload.tags.isEmpty then [] else [("tags", toJson payload.tags)]) ++
      (if payload.authors.isEmpty then [] else [("authors", toJson payload.authors)]) ++
      (if payload.relationshipLines.isEmpty then [] else [("relationshipLines", toJson payload.relationshipLines)]) ++
      (if payload.leanRefLines.isEmpty then [] else [("leanRefLines", toJson payload.leanRefLines)])

instance : ToJson PresentationMode where
  toJson
    | .compact => toJson "compact"
    | .rich => toJson "rich"

instance : ToJson BodyRenderMode where
  toJson
    | .none => toJson "none"
    | .preview => toJson "preview"
    | .full => toJson "full"

private def normalizeOptionalText (text? : Option String) : Option String :=
  text?.bind fun text =>
    let trimmed := text.trimAscii.toString
    if trimmed.isEmpty then none else some trimmed

private def sortStrings (values : Array String) : Array String :=
  values.qsort fun a b => a < b

private def relationshipLine (rel : Relationship) : String :=
  let label := rel.label?.map (fun value => s!" — {value}") |>.getD ""
  let note := rel.note?.map (fun value => s!" ({value})") |>.getD ""
  s!"{rel.kind.asString}: {rel.target}{label}{note}"

private def leanRefLine (ref : LeanDeclRef) : String :=
  let modulePrefix := ref.module?.map (· ++ ".") |>.getD ""
  let kindSuffix := ref.kind?.map (fun value => s!" [{value}]") |>.getD ""
  s!"{modulePrefix}{ref.declaration}{kindSuffix}"

private def previewBodyCore
    (body : String)
    (lineLimit : Nat := 6)
    (charLimit : Nat := 250) : String × Bool :=
  let normalized := body.trimAscii.toString
  if normalized.isEmpty then
    ("", false)
  else
    let lines := normalized.splitOn "\n"
    let selectedLines := lines.take lineLimit
    let lineLimited := String.intercalate "\n" selectedLines
    let chars := lineLimited.toList
    if lines.length > lineLimit then
      (String.ofList (chars.take charLimit), true)
    else if chars.length > charLimit then
      (String.ofList (chars.take charLimit), true)
    else
      (lineLimited, false)

/-- Build a compact summary for a resolved informal reference. -/
def summaryOfResolved (resolved : ResolvedInformalReference) : InformalPresentationSummary :=
  let metadata := resolved.metadata
  {
    ref := resolved.ref
    title := metadata.titleOrId
    kind? := some metadata.kind
    status? := some metadata.status
    summary? := normalizeOptionalText metadata.summary?
  }

/-- Build a richer on-demand presentation payload for a resolved informal reference. -/
def payloadOfResolved
    (resolved : ResolvedInformalReference)
    (bodyMode : BodyRenderMode := .preview) : InformalPresentationPayload :=
  let metadata := resolved.metadata
  let relationshipLines := sortStrings <| metadata.relationships.map relationshipLine
  let leanRefLines := sortStrings <| metadata.leanRefs.map leanRefLine
  let body :=
    match bodyMode with
    | .none => InformalBodyPresentation.none
    | .preview =>
        let (text, truncated) := previewBodyCore resolved.body
        if text.isEmpty then .none else .preview text truncated
    | .full =>
        let text := resolved.body.trimAscii.toString
        if text.isEmpty then .none else .full text
  {
    summary := summaryOfResolved resolved
    tags := sortStrings metadata.tags
    authors := sortStrings metadata.authors
    relationshipLines := relationshipLines
    leanRefLines := leanRefLines
    body := body
  }

private def baseSummaryLines (summary : InformalPresentationSummary) : List String :=
  [ s!"Informal node: {summary.ref}" ] ++
  [ s!"Title: {summary.title}" ] ++
  (match summary.kind? with | some kind => [s!"Kind: {kind}"] | none => []) ++
  (match summary.status? with | some status => [s!"Status: {status}"] | none => []) ++
  (match summary.summary? with | some text => [s!"Summary: {text}"] | none => [])

/-- Render a compact, deterministic text summary. -/
def renderSummaryText (summary : InformalPresentationSummary) : String :=
  String.intercalate "\n" (baseSummaryLines summary)

private def renderSection (title : String) (lines : Array String) : List String :=
  if lines.isEmpty then
    []
  else
    ["", title, String.ofList (List.replicate title.length '-')] ++ lines.toList

/-- Render a richer deterministic text presentation. -/
def renderPayloadText (payload : InformalPresentationPayload) : String :=
  let header := baseSummaryLines payload.summary
  let tags := renderSection "Tags" (payload.tags.map (fun tag => s!"- {tag}"))
  let authors := renderSection "Authors" (payload.authors.map (fun author => s!"- {author}"))
  let relationships := renderSection "Relationships" (payload.relationshipLines.map (fun line => s!"- {line}"))
  let leanRefs := renderSection "Lean refs" (payload.leanRefLines.map (fun line => s!"- {line}"))
  let bodyLines :=
    match payload.body with
    | .none => []
    | .preview text truncated =>
        let trailer := if truncated then #["", "[truncated]"] else #[]
        renderSection "Body" ((text.splitOn "\n").toArray ++ trailer)
    | .full text =>
        renderSection "Body" (text.splitOn "\n" |>.toArray)
  String.intercalate "\n" (header ++ tags ++ authors ++ relationships ++ leanRefs ++ bodyLines)

/-- Render either the compact or rich presentation mode. -/
def renderPresentationText
    (resolved : ResolvedInformalReference)
    (mode : PresentationMode := .rich)
    (bodyMode : BodyRenderMode := .preview) : String :=
  match mode with
  | .compact => renderSummaryText (summaryOfResolved resolved)
  | .rich => renderPayloadText (payloadOfResolved resolved bodyMode)

end AFTK.Informal
