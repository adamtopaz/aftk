import Lake

open Lake DSL System

package aftk where
  version := v!"0.1.0"

require lean_worker from git "https://github.com/adamtopaz/lean_worker" @ "main"

@[default_target]
lean_lib AFTK

@[default_target]
lean_lib Informalize

@[default_target]
lean_lib Tests

@[default_target]
lean_exe aftk_file_worker where
  root := `AFTK.FileWorker
  supportInterpreter := true

@[default_target]
lean_exe aftk_server where
  root := `AFTK.Server
  supportInterpreter := true

@[default_target]
lean_exe informalize where
  root := `InformalizeCli
  supportInterpreter := true

@[default_target]
lean_exe tests where
  root := `Tests
  supportInterpreter := true

private def formatPackageMatches (pkgs : Array Lake.Package) : String :=
  String.intercalate "\n" <|
    pkgs.toList.map fun pkg =>
      s!"- base={pkg.baseName}, orig={pkg.origName}, dir={pkg.dir}"

private def findAftkPackage (ws : Lake.Workspace) : Except String Lake.Package := do
  let candidates := ws.packages.filter fun pkg => pkg.origName == `aftk || pkg.baseName == `aftk
  match candidates with
  | #[] =>
    throw "No `aftk` package was found in this Lake workspace. Add AFTK as a dependency first."
  | #[pkg] =>
    return pkg
  | _ =>
    throw <| String.intercalate "\n" [
      "Multiple packages matched `aftk`.",
      "Please invoke the script with an explicit package prefix, e.g. `lake run aftk/setup_pi_extension`.",
      formatPackageMatches candidates
    ]

private def extensionPathCandidates (aftkPkg : Lake.Package) : Array FilePath := #[
  aftkPkg.dir / "extensions" / "aftk-hub.ts",
  aftkPkg.dir / ".pi" / "extensions" / "aftk-hub.ts"
]

private def findExtensionPath (aftkPkg : Lake.Package) : IO (Option FilePath) := do
  for candidate in extensionPathCandidates aftkPkg do
    if (← candidate.pathExists) then
      return some candidate
  return none

private def setupPiExtensionUsage : String :=
  String.intercalate "\n" [
    "Install the AFTK pi extension into the current project.",
    "",
    "Usage:",
    "  lake run setup_pi_extension",
    "  lake run aftk/setup_pi_extension",
    "",
    "The script finds the AFTK dependency in the current Lake workspace and runs:",
    "  pi install -l <path-to-aftk-extension>",
    "",
    "Requires `pi` to be installed and available on PATH."
  ]

/--
Install AFTK's pi extension in the current project via `pi install -l`.

This works both from the AFTK repo itself and from downstream Lake workspaces
that include AFTK as a dependency (including aliased dependencies).
-/
script setup_pi_extension (args) := do
  if args.contains "--help" || args.contains "-h" then
    IO.println setupPiExtensionUsage
    return 0

  unless args.isEmpty do
    throw <| .userError <| String.intercalate "\n\n" [
      s!"unknown arguments: {String.intercalate " " args}",
      setupPiExtensionUsage
    ]

  let ws ← getWorkspace
  let aftkPkg ←
    match findAftkPackage ws with
    | .ok pkg =>
      pure pkg
    | .error message =>
      throw <| .userError message

  let extCandidates := extensionPathCandidates aftkPkg
  let some extPath ← findExtensionPath aftkPkg
    | throw <| .userError <| String.intercalate "\n" <|
      ["Could not locate AFTK pi extension. Looked for:"] ++
      (extCandidates.toList.map (fun p => s!"- {p}"))

  IO.println s!"Installing AFTK pi extension from:\n- {extPath}"

  let child ← IO.Process.spawn {
    cmd := "pi"
    args := #["install", "-l", extPath.toString]
    cwd := some ws.dir
    stdin := .null
    stdout := .inherit
    stderr := .inherit
  }

  let exitCode ← child.wait
  unless exitCode == 0 do
    throw <| .userError s!"`pi install -l` failed with exit code {exitCode}"

  IO.println "Done. Restart pi or run /reload in the target project."
  return 0
