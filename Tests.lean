import Tests.Unit.Basic
import Tests.Unit.Extension
import Tests.Unit.Metadata
import Tests.Integration.Cli
import Tests.Integration.Imports.Top
import Tests.Unit.IdResolution
import Tests.Unit.Negative

def main : IO Unit := do
  Tests.Integration.Cli.run
  IO.println "Informal rewrite test modules compiled and runtime checks passed."
