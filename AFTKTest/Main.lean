module

public section

private def suites : Array String :=
  #["aftk_knowledgebase_test", "aftk_informal_test", "aftk_server_test"]

@[inline] private def printStdout (text : String) : IO Unit := do
  let stdout ← IO.getStdout
  stdout.putStr text
  stdout.flush

@[inline] private def printStderr (text : String) : IO Unit := do
  let stderr ← IO.getStderr
  stderr.putStr text
  stderr.flush

private def runSuite (suite : String) : IO UInt32 := do
  printStdout s!"\n==> {suite}\n"
  let cwd ← IO.currentDir
  let out ← IO.Process.output {
    cmd := "lake"
    args := #["exe", suite]
    cwd := some cwd
  }
  if !out.stdout.isEmpty then
    printStdout out.stdout
  if !out.stderr.isEmpty then
    printStderr out.stderr
  pure out.exitCode

def main (_args : List String) : IO Unit := do
  for suite in suites do
    let exitCode ← runSuite suite
    if exitCode != 0 then
      IO.Process.exit 1
  printStdout "\nAll test suites passed.\n"
  IO.Process.exit 0
