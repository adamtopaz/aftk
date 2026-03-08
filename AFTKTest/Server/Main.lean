module

public import AFTKTest.Server.Assert
public import AFTKTest.Server.Protocol
public import AFTKTest.Server.Worker
public import AFTKTest.Server.Hub
public import AFTKTest.Server.Integration
public import AFTKTest.Server.Process

public section


open AFTKTest.Server

private unsafe def allTests : List TestCase :=
  AFTKTest.Server.Protocol.tests ++
  AFTKTest.Server.Worker.tests ++
  AFTKTest.Server.Hub.tests ++
  AFTKTest.Server.Integration.tests ++
  AFTKTest.Server.Process.tests

unsafe def main (_args : List String) : IO Unit := do
  IO.Process.exit (← AFTKTest.KnowledgeBase.runTestCases allTests)
