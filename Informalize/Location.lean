module

public import Lean
public import Init.Data.String.Legacy

public section

open Lean

namespace Informalize

private def renderComponents (components : Array String) : String :=
  ".".intercalate components.toList

private def mkNameFromComponents (components : Array String) : Name :=
  components.foldl (init := .anonymous) fun acc component =>
    .str acc component

private def isNumericComponent (component : String) : Bool :=
  !component.isEmpty && component.toList.all Char.isDigit

/--
Return the string components of a `Lean.Name`, rejecting numeric components.
-/
def nameComponents (name : Name) : Except String (Array String) := do
  let rec go : Name → Except String (List String)
    | .anonymous =>
      pure []
    | .str parent component => do
      let parts ← go parent
      pure (parts ++ [component])
    | .num _ _ =>
      throw "numeric components are not supported in informal ids"
  return (← go name).toArray

/--
A validated Informalize location id such as `Foo.bar` or `Foo.bar.baz`.
-/
structure LocationId where
  name : Name
  deriving Inhabited, Repr, BEq, Hashable

namespace LocationId

/-- Render a location id as its dotted string form. -/
def render (location : LocationId) : String :=
  match nameComponents location.name with
  | .ok components =>
    renderComponents components
  | .error _ =>
    toString location.name

instance : ToString LocationId := ⟨render⟩

/-- Construct a validated location id from an existing `Lean.Name`. -/
def ofName (name : Name) : Except String LocationId := do
  let components ← nameComponents name
  if components.size < 2 then
    throw s!"informal id `{renderComponents components}` must have at least two components (`Directory.File`)"
  return { name }

/-- Construct a validated location id from a dotted string like `Foo.bar`. -/
def ofDottedString (raw : String) : Except String LocationId := do
  let trimmed := raw.trimAscii.toString
  if trimmed.isEmpty then
    throw "location name must be non-empty"
  let components := (trimmed.splitOn ".").toArray
  if components.any String.isEmpty then
    throw s!"invalid location name `{raw}`"
  if components.any isNumericComponent then
    throw "numeric components are not supported in informal ids"
  if components.size < 2 then
    throw s!"informal id `{renderComponents components}` must have at least two components (`Directory.File`)"
  return {
    name := mkNameFromComponents components
  }

/-- Return the validated string components of a location id. -/
def components (location : LocationId) : Array String :=
  match nameComponents location.name with
  | .ok components =>
    components
  | .error _ =>
    #[]

private def pathWithExtension (location : LocationId) (ext : String) : System.FilePath :=
  let components := location.components
  let pathComponents := Id.run do
    let mut path : Array String := #[]
    for idx in [0:components.size] do
      match components[idx]? with
      | some component =>
        if idx + 1 == components.size then
          path := path.push s!"{component}.{ext}"
        else
          path := path.push component
      | none =>
        pure ()
    return path
  System.FilePath.mk s!"informal/{"/".intercalate pathComponents.toList}"

/-- The markdown sidecar path for a location id. -/
def markdownPath (location : LocationId) : System.FilePath :=
  pathWithExtension location "md"

/-- The metadata sidecar path for a location id. -/
def metadataPath (location : LocationId) : System.FilePath :=
  pathWithExtension location "json"

/--
Load the markdown file for a location id, using the standard Informalize error style.
-/
def readMarkdown (location : LocationId) : IO (Except String String) := do
  let filePath := location.markdownPath
  let pathExists ← filePath.pathExists
  if !pathExists then
    return .error s!"informal id `{location}` points to missing file `{filePath}`"
  try
    return .ok (← IO.FS.readFile filePath)
  catch _ =>
    return .error s!"unable to read `{filePath}` for informal id `{location}`"

/--
Ensure the markdown file for a location id exists and is readable.
-/
def ensureMarkdownExists (location : LocationId) : IO (Except String Unit) := do
  match ← location.readMarkdown with
  | .ok _ =>
    return .ok ()
  | .error err =>
    return .error err

instance : ToJson LocationId where
  toJson location := .str (toString location)

instance : FromJson LocationId where
  fromJson?
    | .str raw =>
      LocationId.ofDottedString raw
    | _ =>
      .error "expected location id string"

end LocationId

end Informalize
