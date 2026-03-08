module

public import AFTK.KnowledgeBase
public import Lean.Data.Json.Parser

public section


namespace AFTKTest.KnowledgeBase

open AFTK.KnowledgeBase
open Lean

abbrev TestM := EIO String

structure TestCase where
  name : String
  run : TestM Unit

private def errorMessageOf (err : KnowledgeBaseError) : String :=
  s!"{err.code}: {err.message}"

@[inline] def liftIO {α : Type} (action : IO α) : TestM α :=
  action.toEIO (fun err => err.toString)

@[inline] def liftKB {α : Type} (action : KBIO α) : TestM α :=
  EIO.adapt errorMessageOf action

@[inline] def fail {α : Type} (message : String) : TestM α :=
  throw message

@[inline] def assertTrue (cond : Bool) (message : String) : TestM Unit :=
  unless cond do fail message

@[inline] def assertFalse (cond : Bool) (message : String) : TestM Unit :=
  assertTrue (!cond) message

@[inline] def assertEq [BEq α] [Repr α] (actual expected : α) (context : String := "") : TestM Unit :=
  unless actual == expected do
    let prefMsg := if context.isEmpty then "" else context ++ "\n"
    fail s!"{prefMsg}expected: {repr expected}\nactual:   {repr actual}"

@[inline] def assertSome [Repr α] (value : Option α) (message : String := "expected some") : TestM α :=
  match value with
  | some value => pure value
  | none => fail message

@[inline] def assertNone [Repr α] (value : Option α) (message : String := "expected none") : TestM Unit :=
  match value with
  | none => pure ()
  | some value => fail s!"{message}\nactual: {repr value}"

@[inline] def assertContains (haystack needle : String) (context : String := "") : TestM Unit :=
  unless haystack.contains needle do
    let prefMsg := if context.isEmpty then "" else context ++ "\n"
    fail s!"{prefMsg}expected substring: {needle}\nactual text:\n{haystack}"

@[inline] def assertExceptErrorContains {α : Type} (result : Except String α) (needle : String) : TestM Unit :=
  match result with
  | .ok _ => fail s!"expected error containing '{needle}', but computation succeeded"
  | .error err => assertContains err needle

@[inline] def assertJsonParses (text : String) : TestM Json :=
  match Json.parse text with
  | .ok json => pure json
  | .error err => fail s!"expected valid JSON, got parse error: {err}\n{text}"

@[inline] def assertThrowsContains {α : Type} (action : TestM α) (needle : String) : TestM Unit := do
  let result ← liftIO <| action.toIO'
  match result with
  | .ok _ => fail s!"expected failure containing '{needle}', but computation succeeded"
  | .error err => assertContains err needle

@[inline] def withTempDir {α : Type} (f : System.FilePath → TestM α) : TestM α := do
  let dir ← liftIO IO.FS.createTempDir
  try
    f dir
  finally
    discard <| liftIO <| IO.FS.removeDirAll dir

@[inline] def readGolden (name : String) : TestM String := do
  let cwd ← liftIO IO.currentDir
  liftIO <| IO.FS.readFile (cwd / "tests" / "knowledgebase" / "golden" / name)

@[inline] private def printStdoutLine (line : String) : IO Unit := do
  let stdout ← IO.getStdout
  stdout.putStrLn line
  stdout.flush

@[inline] private def printStderrLine (line : String) : IO Unit := do
  let stderr ← IO.getStderr
  stderr.putStrLn line
  stderr.flush

@[inline] def runTestCase (test : TestCase) : IO Bool := do
  printStdoutLine s!"[RUN] {test.name}"
  let result ← test.run.toIO'
  match result with
  | .ok _ =>
      printStdoutLine s!"[PASS] {test.name}"
      pure true
  | .error err =>
      printStderrLine s!"[FAIL] {test.name}\n{err}"
      pure false

@[inline] def runTestCases (tests : List TestCase) : IO UInt8 := do
  let mut passed := 0
  let mut failed := 0
  for test in tests do
    if ← runTestCase test then
      passed := passed + 1
    else
      failed := failed + 1
  printStdoutLine ""
  printStdoutLine s!"Test summary: {passed} passed; {failed} failed"
  pure <| if failed == 0 then 0 else 1

end AFTKTest.KnowledgeBase
