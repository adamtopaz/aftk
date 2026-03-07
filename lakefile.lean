import Lake

open Lake DSL System

package aftk where
  version := v!"0.1.0"

require lean_worker from git "https://github.com/adamtopaz/lean_worker" @ "main"

@[default_target]
lean_lib AFTK

@[default_target]
lean_lib Informalize

lean_lib Tests

@[default_target]
lean_exe aftk where
  root := `AFTKCli
  supportInterpreter := true

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

lean_exe tests where
  root := `TestsMain
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

private def piPackagePath (aftkPkg : Lake.Package) : FilePath :=
  aftkPkg.dir

private def piExtensionEntryPoint (aftkPkg : Lake.Package) : FilePath :=
  aftkPkg.dir / "lambda" / "src" / "aftk-extension.ts"

private def setupPiExtensionUsage : String :=
  String.intercalate "\n" [
    "Install the AFTK pi package into the current project.",
    "",
    "Usage:",
    "  lake run setup_pi_extension",
    "  lake run aftk/setup_pi_extension",
    "",
    "The script finds the AFTK dependency, ensures its TypeScript dependencies are installed,",
    "and runs:",
    "  pi install -l <path-to-aftk-package>",
    "",
    "Requires `pi` to be installed and available on PATH.",
    "Requires `bun` too when AFTK's `node_modules/` is missing."
  ]

private def ensurePiPackageDependencies (aftkPkg : Lake.Package) : IO Unit := do
  let nodeModulesDir := aftkPkg.dir / "node_modules"
  if (← nodeModulesDir.pathExists) then
    return

  IO.println s!"Installing AFTK TypeScript dependencies in:\n- {aftkPkg.dir}"

  let child ← IO.Process.spawn {
    cmd := "bun"
    args := #["install"]
    cwd := some aftkPkg.dir
    stdin := .inherit
    stdout := .inherit
    stderr := .inherit
  }

  let exitCode ← child.wait
  unless exitCode == 0 do
    throw <| .userError s!"`bun install` failed with exit code {exitCode}"

/--
Install AFTK's pi package in the current project via `pi install -l`.

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

  let packagePath := piPackagePath aftkPkg
  let packageJson := packagePath / "package.json"
  unless (← packageJson.pathExists) do
    throw <| .userError <| String.intercalate "\n" [
      "Could not locate AFTK pi package manifest.",
      s!"Expected: {packageJson}"
    ]

  let extPath := piExtensionEntryPoint aftkPkg
  unless (← extPath.pathExists) do
    throw <| .userError <| String.intercalate "\n" [
      "Could not locate AFTK pi extension entrypoint.",
      s!"Expected: {extPath}"
    ]

  try
    ensurePiPackageDependencies aftkPkg
  catch err =>
    throw <| .userError <| String.intercalate "\n\n" [
      "Failed to prepare AFTK TypeScript dependencies. Ensure `bun` is installed and on PATH.",
      toString err
    ]

  IO.println s!"Installing AFTK pi package from:\n- {packagePath}"

  let child ← IO.Process.spawn {
    cmd := "pi"
    args := #["install", "-l", packagePath.toString]
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

