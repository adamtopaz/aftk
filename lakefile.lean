import Lake

open System Lake DSL

package aftk where
  testDriver := "aftk_test"
  version := v!"0.1.0"

require lean_worker from git "https://github.com/adamtopaz/lean_worker"@"main"

private def hasHydraConfigPathFlag (args : List String) : Bool :=
  args.any fun arg =>
    arg == "--config-path" || arg == "-cp" || arg.startsWith "--config-path=" || arg.startsWith "-cp="

private def hasHydraJobLoggingOverride (args : List String) : Bool :=
  args.any fun arg =>
    arg.startsWith "hydra.job_logging." || arg.startsWith "hydra/job_logging="

private def hasHydraHydraLoggingOverride (args : List String) : Bool :=
  args.any fun arg =>
    arg.startsWith "hydra.hydra_logging." || arg.startsWith "hydra/hydra_logging="

private def defaultHydraLoggingArgs (args : List String) : Array String :=
  let jobLoggingArgs :=
    if hasHydraJobLoggingOverride args then
      #[]
    else
      #["hydra.job_logging.handlers.console.stream=ext://sys.stderr"]
  let hydraLoggingArgs :=
    if hasHydraHydraLoggingOverride args then
      #[]
    else
      #["hydra.hydra_logging.handlers.console.stream=ext://sys.stderr"]
  jobLoggingArgs ++ hydraLoggingArgs

private def runAftkPythonCli (scriptName : String) (args : List String) : ScriptM UInt32 := do
  let ws ← getWorkspace
  let some pkg ← findPackageByName? `aftk
    | error "workspace is missing package `aftk`"
  let configPathArgs :=
    if hasHydraConfigPathFlag args then
      #[]
    else
      #["--config-path", ws.dir.toString]
  let forwardedArgs :=
    configPathArgs ++ defaultHydraLoggingArgs args ++ args.toArray
  let child ← IO.Process.spawn {
    cmd := "uv"
    args := #["run", "--project", pkg.dir.toString, scriptName] ++ forwardedArgs
    cwd := ws.dir
    env := ← getAugmentedEnv
  }
  return ← child.wait

/-- Run the Python AFTK CLI via `uv run aftk`, using the AFTK package as the uv project while keeping the caller workspace as the working directory. By default, the launcher points Hydra at the caller workspace root so `config.yaml` is resolved from the downstream project. -/
script aftk (args) do
  runAftkPythonCli "aftk" args

/-- Run the interactive Python AFTK chat CLI via `uv run aftk_chat`, using the AFTK package as the uv project while keeping the caller workspace as the working directory. By default, the launcher points Hydra at the caller workspace root so `config.yaml` is resolved from the downstream project. -/
script aftk_chat (args) do
  runAftkPythonCli "aftk_chat" args

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
