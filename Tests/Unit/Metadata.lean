import Informalize

open Lean Elab Command

namespace Tests.Unit.Metadata

run_cmd do
  unless toJson (Informalize.NodeStatus.ready) == .str "ready" do
    throwError "expected `NodeStatus.ready` to encode as `ready`"

  match fromJson? (α := Informalize.NodeStatus) (.str "needs_sources") with
  | .ok .needsSources =>
    pure ()
  | .ok other =>
    throwError s!"unexpected parsed status: {other}"
  | .error err =>
    throwError s!"failed to parse valid node status: {err}"

run_cmd do
  let json := Json.mkObj [
    ("status", .str "formalizing")
  ]
  let metadata ←
    match fromJson? (α := Informalize.Metadata) json with
    | .ok metadata =>
      pure metadata
    | .error err =>
      throwError s!"failed to parse defaulted metadata: {err}"
  unless metadata.schemaVersion == 1 do
    throwError "expected default schemaVersion = 1"
  unless metadata.status == .formalizing do
    throwError "expected parsed status = formalizing"
  unless metadata.sources.isEmpty && metadata.knowledgeRefs.isEmpty && metadata.issues.isEmpty && metadata.tags.isEmpty do
    throwError "expected missing array fields to default to empty arrays"

run_cmd do
  match Informalize.LocationId.ofDottedString "Foo.bar" with
  | .error err =>
    throwError s!"failed to parse location id: {err}"
  | .ok location =>
    let loaded : Informalize.LoadedMetadata := {
      metadata := Informalize.Metadata.default,
      origin := .default
    }
    let hover := Informalize.LoadedMetadata.renderHoverText location loaded "# Notes\ntext"
    unless hover.contains "Informalize location: Foo.bar" do
      throwError "hover text should mention the location id"
    unless hover.contains "Metadata source: default" do
      throwError "hover text should mention default metadata origin"
    unless hover.contains "status: scaffolded" do
      throwError "hover text should include metadata summary"
    unless hover.contains "# Notes" do
      throwError "hover text should include markdown notes"

run_cmd do
  match fromJson? (α := Informalize.Metadata) (Json.mkObj [("status", .str "bad_value")]) with
  | .ok _ =>
    throwError "expected invalid status string to fail metadata parsing"
  | .error _ =>
    pure ()

end Tests.Unit.Metadata
