module

public import Lean
public import Informalize.Location
public import AFTK.Util

public section

open Lean

namespace AFTK

private def isValidIdComponentChar (c : Char) : Bool :=
  c.isAlphanum || c == '_' || c == '-'

private def validateIdComponents (label family : String) (raw : String) : Except String (Array String) := do
  let trimmed ← nonEmptyText label raw
  let components := (trimmed.splitOn ".").toArray
  if components.size < 2 then
    throw s!"{label} `{trimmed}` must have at least two components"
  if components[0]! != family then
    throw s!"{label} `{trimmed}` must start with `{family}.`"
  for component in components do
    if component.isEmpty then
      throw s!"invalid {label} `{raw}`"
    if !(component.toList.all isValidIdComponentChar) then
      throw s!"invalid {label} component `{component}` in `{raw}`"
  return components

private def suffixComponents (raw : String) : Array String :=
  let components := (raw.splitOn ".").toArray
  components.extract 1 components.size

private def foldPathComponents (base : System.FilePath) (components : Array String) : System.FilePath :=
  components.foldl (fun acc component => acc / System.FilePath.mk component) base

private def jsonPathFor (subdir : String) (root : System.FilePath) (raw : String) : System.FilePath :=
  let components := suffixComponents raw
  let pathComponents := Id.run do
    let mut out : Array String := #[]
    for idx in [0:components.size] do
      let component := components[idx]!
      if idx + 1 == components.size then
        out := out.push s!"{component}.json"
      else
        out := out.push component
    return out
  foldPathComponents (root / subdir) pathComponents

private def bodyPathFor (subdir : String) (root : System.FilePath) (raw : String) : System.FilePath :=
  let components := suffixComponents raw
  let pathComponents := Id.run do
    let mut out : Array String := #[]
    for idx in [0:components.size] do
      let component := components[idx]!
      if idx + 1 == components.size then
        out := out.push s!"{component}.md"
      else
        out := out.push component
    return out
  foldPathComponents (root / subdir) pathComponents

structure SourceId where
  raw : String
  deriving Inhabited, Repr, BEq, Hashable

namespace SourceId

def ofString (raw : String) : Except String SourceId := do
  let _ ← validateIdComponents "source id" "src" raw
  return { raw := normalizeText raw }

def components (id : SourceId) : Array String :=
  (id.raw.splitOn ".").toArray

def jsonPath (root : System.FilePath) (id : SourceId) : System.FilePath :=
  jsonPathFor "sources" root id.raw

def render (id : SourceId) : String :=
  id.raw

instance : ToString SourceId := ⟨render⟩

instance : ToJson SourceId where
  toJson id := .str id.raw

instance : FromJson SourceId where
  fromJson?
    | .str raw => ofString raw
    | _ => .error "expected source id string"

end SourceId

structure PacketId where
  raw : String
  deriving Inhabited, Repr, BEq, Hashable

namespace PacketId

def ofString (raw : String) : Except String PacketId := do
  let _ ← validateIdComponents "packet id" "pkt" raw
  return { raw := normalizeText raw }

def components (id : PacketId) : Array String :=
  (id.raw.splitOn ".").toArray

def jsonPath (root : System.FilePath) (id : PacketId) : System.FilePath :=
  jsonPathFor "packets" root id.raw

def bodyPath (root : System.FilePath) (id : PacketId) : System.FilePath :=
  bodyPathFor "packets" root id.raw

def render (id : PacketId) : String :=
  id.raw

instance : ToString PacketId := ⟨render⟩

instance : ToJson PacketId where
  toJson id := .str id.raw

instance : FromJson PacketId where
  fromJson?
    | .str raw => ofString raw
    | _ => .error "expected packet id string"

end PacketId

structure KnowledgeId where
  raw : String
  deriving Inhabited, Repr, BEq, Hashable

namespace KnowledgeId

def ofString (raw : String) : Except String KnowledgeId := do
  let _ ← validateIdComponents "knowledge id" "kb" raw
  return { raw := normalizeText raw }

def components (id : KnowledgeId) : Array String :=
  (id.raw.splitOn ".").toArray

def jsonPath (root : System.FilePath) (id : KnowledgeId) : System.FilePath :=
  jsonPathFor "knowledge" root id.raw

def bodyPath (root : System.FilePath) (id : KnowledgeId) : System.FilePath :=
  bodyPathFor "knowledge" root id.raw

def render (id : KnowledgeId) : String :=
  id.raw

instance : ToString KnowledgeId := ⟨render⟩

instance : ToJson KnowledgeId where
  toJson id := .str id.raw

instance : FromJson KnowledgeId where
  fromJson?
    | .str raw => ofString raw
    | _ => .error "expected knowledge id string"

end KnowledgeId

inductive ProvenanceTargetKind where
  | source
  | packet
  | knowledge
  | scaffold
  deriving Inhabited, Repr, BEq

namespace ProvenanceTargetKind

def encoded : ProvenanceTargetKind → String
  | .source => "source"
  | .packet => "packet"
  | .knowledge => "knowledge"
  | .scaffold => "scaffold"

instance : ToString ProvenanceTargetKind := ⟨encoded⟩

instance : ToJson ProvenanceTargetKind where
  toJson kind := .str (toString kind)

instance : FromJson ProvenanceTargetKind where
  fromJson?
    | .str "source" => .ok .source
    | .str "packet" => .ok .packet
    | .str "knowledge" => .ok .knowledge
    | .str "scaffold" => .ok .scaffold
    | .str other => .error s!"invalid provenance target kind `{other}`"
    | _ => .error "expected provenance target kind string"

end ProvenanceTargetKind

def validateTargetIdForKind (kind : ProvenanceTargetKind) (raw : String) : Except String Unit := do
  match kind with
  | .source =>
    let _ ← SourceId.ofString raw
    pure ()
  | .packet =>
    let _ ← PacketId.ofString raw
    pure ()
  | .knowledge =>
    let _ ← KnowledgeId.ofString raw
    pure ()
  | .scaffold =>
    let _ ← Informalize.LocationId.ofDottedString raw
    pure ()

end AFTK
