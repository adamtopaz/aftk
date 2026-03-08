import AFTKTest.Server.Assert
import AFTKTest.Server.Protocol
import AFTKTest.Server.Worker
import AFTKTest.Server.Hub
import AFTKTest.Server.Integration
import AFTKTest.Server.Process

open AFTKTest.Server

private unsafe def allTests : List TestCase :=
  AFTKTest.Server.Protocol.tests ++
  AFTKTest.Server.Worker.tests ++
  AFTKTest.Server.Hub.tests ++
  AFTKTest.Server.Integration.tests ++
  AFTKTest.Server.Process.tests

unsafe def main (_args : List String) : IO Unit := do
  IO.Process.exit (← AFTKTest.KnowledgeBase.runTestCases allTests)
