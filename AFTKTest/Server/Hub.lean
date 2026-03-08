module

public import AFTK.Server.Hub
public import AFTKTest.Server.Assert
public import AFTKTest.Server.Fixtures

public section


namespace AFTKTest.Server.Hub

open AFTKTest.Server
open AFTKTest.Server.Fixtures

private def resolveIdentity : TestCase := {
  name := "server.hub.resolveIdentity"
  run := do
    let path := (← semanticsPath).toString
    let identity ← liftIO <| AFTK.Server.Hub.resolveFileIdentityIO path
    assertTrue identity.normalizedPath.isAbsolute "normalized path should be absolute"
    assertContains identity.normalizedPath.toString "tests/server/fixtures/lean/Semantics.lean"
    assertEq identity.normalizedPath identity.canonicalPath
}

private def readFileStamp : TestCase := {
  name := "server.hub.readFileStamp"
  run := do
    let path ← semanticsPath
    match ← liftIO <| AFTK.Server.Hub.readFileStampIO path with
    | .error err => fail s!"{err.code}: {err.message}"
    | .ok stamp => assertTrue (stamp.byteSize > 0) "fixture file should be non-empty"
}

private def readFileStampRejectsDirectory : TestCase := {
  name := "server.hub.readFileStampRejectsDirectory"
  run := do
    let dir ← liftIO IO.currentDir
    match ← liftIO <| AFTK.Server.Hub.readFileStampIO dir with
    | .ok _ => fail "expected directory stamp read to fail"
    | .error err =>
        assertEq err.message "Invalid params"
        let data := err.data?.map (fun json => json.compress) |>.getD ""
        assertContains data "not a regular file"
}


def tests : List TestCase :=
  [resolveIdentity, readFileStamp, readFileStampRejectsDirectory]

end AFTKTest.Server.Hub
