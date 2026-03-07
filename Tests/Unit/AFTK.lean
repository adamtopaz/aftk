import AFTK

open Lean Elab Command

namespace Tests.Unit.AFTK

run_cmd do
  let sourceId ←
    match AFTK.SourceId.ofString "src.paper.smith2024" with
    | .ok id =>
      pure id
    | .error err =>
      throwError s!"expected valid source id: {err}"
  unless toString sourceId == "src.paper.smith2024" do
    throwError "unexpected source id rendering"
  unless toString (sourceId.jsonPath (System.FilePath.mk "aftk-data")) == "aftk-data/sources/paper/smith2024.json" do
    throwError "unexpected source id path mapping"

run_cmd do
  match AFTK.PacketId.ofString "pkt.paper.smith2024.thm_2_3" with
  | .error err =>
    throwError s!"expected valid packet id: {err}"
  | .ok packetId =>
    unless toString (packetId.bodyPath (System.FilePath.mk "aftk-data")) == "aftk-data/packets/paper/smith2024/thm_2_3.md" do
      throwError "unexpected packet body path mapping"

run_cmd do
  match AFTK.SourceId.ofString "bad.paper.demo" with
  | .ok _ =>
    throwError "expected invalid source family prefix to fail"
  | .error _ =>
    pure ()

run_cmd do
  match AFTK.KnowledgeEntry.validate {
    id := (match AFTK.KnowledgeId.ofString "kb.demo.entry" with | .ok id => id | .error _ => default),
    kind := .definition,
    basis := .sourceBacked,
    title := "Demo",
    provenance := #[]
  } with
  | .ok () =>
    throwError "expected source-backed knowledge without support to fail"
  | .error _ =>
    pure ()

end Tests.Unit.AFTK
