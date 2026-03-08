import AFTKTest.KnowledgeBase.Assert
import AFTKTest.KnowledgeBase.Types
import AFTKTest.KnowledgeBase.PathLayout
import AFTKTest.KnowledgeBase.Serialization
import AFTKTest.KnowledgeBase.Storage
import AFTKTest.KnowledgeBase.Validation
import AFTKTest.KnowledgeBase.Search
import AFTKTest.KnowledgeBase.Cli

private def allTests : List AFTKTest.KnowledgeBase.TestCase :=
  AFTKTest.KnowledgeBase.Types.tests ++
  AFTKTest.KnowledgeBase.PathLayout.tests ++
  AFTKTest.KnowledgeBase.Serialization.tests ++
  AFTKTest.KnowledgeBase.Storage.tests ++
  AFTKTest.KnowledgeBase.Validation.tests ++
  AFTKTest.KnowledgeBase.Search.tests ++
  AFTKTest.KnowledgeBase.Cli.tests

def main (_args : List String) : IO Unit := do
  IO.Process.exit (← AFTKTest.KnowledgeBase.runTestCases allTests)
