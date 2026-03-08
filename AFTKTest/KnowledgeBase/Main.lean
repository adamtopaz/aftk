module

public import AFTKTest.KnowledgeBase.Assert
public import AFTKTest.KnowledgeBase.Types
public import AFTKTest.KnowledgeBase.PathLayout
public import AFTKTest.KnowledgeBase.Serialization
public import AFTKTest.KnowledgeBase.Storage
public import AFTKTest.KnowledgeBase.Validation
public import AFTKTest.KnowledgeBase.Search
public import AFTKTest.KnowledgeBase.Cli

public section


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
