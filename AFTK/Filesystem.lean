module

public import Lean

public section

namespace AFTK

private def ensureParentDir (path : System.FilePath) : IO Unit := do
  if let some dir := path.parent then
    IO.FS.createDirAll dir

private def removeFileIfExists (path : System.FilePath) : IO Unit := do
  if (← path.pathExists) then
    IO.FS.removeFile path

/-- Write a text file atomically via a temporary sibling path. -/
def writeFileAtomic (path : System.FilePath) (contents : String) : IO Unit := do
  ensureParentDir path
  let tempPath := System.FilePath.mk s!"{path}.tmp"
  removeFileIfExists tempPath
  IO.FS.writeFile tempPath contents
  IO.FS.rename tempPath path

/-- Write pretty JSON with a trailing newline. -/
def writeJsonAtomic (path : System.FilePath) (json : Lean.Json) : IO Unit := do
  writeFileAtomic path (json.pretty ++ "\n")

/-- Read and parse a JSON file, wrapping file-specific errors clearly. -/
def readJsonFile (label : String) (path : System.FilePath) : IO (Except String Lean.Json) := do
  if !(← path.pathExists) then
    return .error s!"missing {label} file `{path}`"
  let contents ←
    try
      pure <| Except.ok (← IO.FS.readFile path)
    catch _ =>
      pure <| Except.error s!"unable to read {label} file `{path}`"
  match contents with
  | .error err =>
    return .error err
  | .ok contents =>
    match Lean.Json.parse contents with
    | .ok json =>
      return .ok json
    | .error err =>
      return .error s!"invalid JSON in `{path}`: {err}"

/-- Read a text sidecar with a consistent error style. -/
def readTextFile (label : String) (path : System.FilePath) : IO (Except String String) := do
  if !(← path.pathExists) then
    return .error s!"missing {label} file `{path}`"
  try
    return .ok (← IO.FS.readFile path)
  catch _ =>
    return .error s!"unable to read {label} file `{path}`"

end AFTK
