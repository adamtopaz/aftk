import Lake

open System Lake DSL

package aftk where
  testDriver := "aftk_test"
  version := v!"0.1.0"

require lean_worker from git "https://github.com/adamtopaz/lean_worker"@"main"

/-- Run the Python AFTK CLI via `uv run aftk` from the AFTK package directory. -/
script aftk (args) do
  let some pkg ← findPackageByName? `aftk
    | error "workspace is missing package `aftk`"
  let child ← IO.Process.spawn {
    cmd := "uv"
    args := #["run", "aftk"] ++ args.toArray
    cwd := pkg.dir
    env := ← getAugmentedEnv
  }
  return ← child.wait

lean_lib AFTK

lean_lib AFTKTest

@[default_target] lean_exe aftk_cli where
  root := `Main
  exeName := "aftk"
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
