module

public import AFTK.Cli

public section

def main (args : List String) : IO UInt32 := do
  let result ← AFTK.Cli.invoke args.toArray
  unless result.stdout.isEmpty do
    IO.println result.stdout
  unless result.stderr.isEmpty do
    IO.eprintln result.stderr
  return result.exitCode
