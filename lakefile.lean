import Lake

open System Lake DSL

package aftk where
  testDriver := "aftk_test"
  version := v!"0.1.0"

require lean_worker from git "https://github.com/adamtopaz/lean_worker"@"main"

lean_lib AFTK

lean_lib AFTKTest

@[default_target] lean_exe aftk where
  root := `Main
  supportInterpreter := true

lean_exe aftk_server where
  root := `AFTK.Server.Main
  supportInterpreter := true

lean_exe aftk_file_worker where
  root := `AFTK.FileWorker.Main
  supportInterpreter := true

lean_exe aftk_knowledgebase_test where
  root := `AFTKTest.KnowledgeBase.Main
  supportInterpreter := true

lean_exe aftk_informal_test where
  root := `AFTKTest.Informal.Main
  supportInterpreter := true

lean_exe aftk_server_test where
  root := `AFTKTest.Server.Main
  supportInterpreter := true

lean_exe aftk_test where
  root := `AFTKTest.Main
  supportInterpreter := true

/--
Run the AFTK Python autoformalization framework against the current root Lake project.

This is intended to work both in this repository and when `aftk` is used as a Lake dependency.
The script always launches the Python CLI with the working directory set to the root Lake project,
while resolving the Python package and its dependencies from the `aftk` package directory.

Usage:
  lake run autoformalize <hydra overrides>

Example:
  lake run autoformalize \
    models.initializer='openai:gpt-5-mini' \
    models.orchestrator='openai:gpt-5' \
    models.worker='openai:gpt-5-mini'
-/
script autoformalize (args) do
  let rootPkg ← getRootPackage
  let some aftkPkg ← findPackageByName? `aftk
    | error "could not locate the `aftk` package in the current Lake workspace"
  let child ← IO.Process.spawn {
    cmd := "uv"
    args := #[("run" : String), "--project", aftkPkg.dir.toString, "autoformalize"] ++ args.toArray
    cwd := rootPkg.dir
  }
  return (← child.wait)
