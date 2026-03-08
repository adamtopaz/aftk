import AFTKTest.KnowledgeBase
import AFTKTest.Informal

private unsafe def allTests : List AFTKTest.KnowledgeBase.TestCase :=
  AFTKTest.KnowledgeBase.Types.tests ++
  AFTKTest.KnowledgeBase.PathLayout.tests ++
  AFTKTest.KnowledgeBase.Serialization.tests ++
  AFTKTest.KnowledgeBase.Storage.tests ++
  AFTKTest.KnowledgeBase.Validation.tests ++
  AFTKTest.KnowledgeBase.Search.tests ++
  AFTKTest.KnowledgeBase.Cli.tests ++
  AFTKTest.Informal.References.tests ++
  AFTKTest.Informal.Placeholder.tests ++
  AFTKTest.Informal.Tracking.tests ++
  AFTKTest.Informal.Dependencies.tests ++
  AFTKTest.Informal.Presentation.tests ++
  AFTKTest.Informal.Elaboration.tests ++
  AFTKTest.Informal.Cli.tests

unsafe def main (_args : List String) : IO Unit := do
  IO.Process.exit (← AFTKTest.KnowledgeBase.runTestCases allTests)
