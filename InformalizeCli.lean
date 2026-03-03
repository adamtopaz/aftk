module

public import Informalize.Cli

public section

def main (args : List String) : IO UInt32 := do
  let result ← Informalize.Cli.invoke args.toArray
  unless result.stdout.isEmpty do
    IO.println result.stdout
  unless result.stderr.isEmpty do
    IO.eprintln result.stderr
  return result.exitCode
