import AFTKTest.KnowledgeBase.Assert

namespace AFTKTest.Informal

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

end AFTKTest.Informal
