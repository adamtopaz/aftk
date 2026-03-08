module

public import AFTKTest.KnowledgeBase.Assert

public section


namespace AFTKTest.Server

abbrev TestM := AFTKTest.KnowledgeBase.TestM
abbrev TestCase := AFTKTest.KnowledgeBase.TestCase

export AFTKTest.KnowledgeBase (
  liftIO
  fail
  assertTrue
  assertFalse
  assertEq
  assertSome
  assertNone
  assertContains
  assertExceptErrorContains
  assertJsonParses
  assertThrowsContains
  withTempDir
)

end AFTKTest.Server
