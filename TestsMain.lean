import Tests


def main (_args : List String) : IO UInt32 := do
  Tests.Integration.Cli.run
  Tests.Integration.AFTKCli.run
  IO.println "Informal rewrite test modules compiled and runtime checks passed."
  return 0
