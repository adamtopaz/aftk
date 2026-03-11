module

public import AFTK.KnowledgeBase.Cli.Parse
public import AFTK.KnowledgeBase.Cli.Render
public import AFTK.KnowledgeBase.Service

public section


namespace AFTK.KnowledgeBase
namespace Cli

open PathLayout

namespace Main

private def liftIO {α : Type} (action : IO α) : KBIO α :=
  action.toEIO (fun err => KnowledgeBaseError.generic "io.error" err.toString 1)

private def readInputSource : InputSource → IO String
  | .stdin => do
      let stdin ← IO.getStdin
      stdin.readToEnd
  | .file path => IO.FS.readFile path

private def loadMetadataReplacement (source : InputSource) : KBIO NodeMetadata := do
  let text ← liftIO <| readInputSource source
  match Serialization.parseNodeMetadataText text with
  | .ok metadata => pure metadata
  | .error err => throw <| KnowledgeBaseError.validation "metadata.parseError" s!"Invalid metadata input: {err}"

private def loadBodyInput (source? : Option InputSource) : IO String := do
  match source? with
  | some source => readInputSource source
  | none => pure ""

private def dispatch (root : System.FilePath) : Command → KBIO CommandResult
  | .init =>
      CommandResult.init <$> Service.initAtRoot root
  | .status =>
      CommandResult.status <$> Service.statusInfoForRoot root
  | .list opts => do
      return .list (← Service.listAtRoot root opts.prefix? opts.kind? opts.status? opts.tag?)
  | .show id .combined =>
      .show <$> Service.showNodeAtRoot root id
  | .show id .body => do
      pure <| .body id (← Service.getBodyAtRoot root id)
  | .show id .metadata => do
      pure <| .metadata (← Service.getMetadataAtRoot root id)
  | .show id .paths => do
      pure <| .paths id (← Service.getPathsAtRoot root id)
  | .create id opts => do
      let body ← liftIO <| loadBodyInput opts.bodySource?
      .create <$> Service.createAtRoot root id opts.title body opts.kind opts.status opts.summary? opts.tags opts.authors
  | .rename oldId newId =>
      .rename oldId <$> Service.renameAtRoot root oldId newId
  | .delete id => do
      Service.deleteAtRoot root id
      pure <| .delete id
  | .body (.show id) => do
      pure <| .body id (← Service.getBodyAtRoot root id)
  | .body (.set id source) => do
      let body ← liftIO <| readInputSource source
      .show <$> Service.setBodyAtRoot root id body
  | .metadata (.show id) => do
      pure <| .metadata (← Service.getMetadataAtRoot root id)
  | .metadata (.replace id source) => do
      let metadata ← loadMetadataReplacement source
      .show <$> Service.replaceMetadataAtRoot root id metadata
  | .metadata (.validate id) => do
      return .validation (← Service.validateMetadataAtRoot root id)
  | .validate .storage => do
      return .validation (← Service.validateStorageAtRoot root)
  | .validate (.node id) => do
      return .validation (← Service.validateNodeAtRoot root id)
  | .validate .all => do
      return .validation (← Service.validateAllAtRoot root)
  | .search (.text query limit?) =>
      .search <$> Service.searchTextAtRoot root query limit?
  | .search (.tag tag limit?) =>
      .search <$> Service.searchTagAtRoot root tag limit?
  | .relationships (.outgoing id) =>
      .outgoingRelationships id <$> Service.outgoingRelationshipsAtRoot root id
  | .relationships (.incoming id) =>
      .incomingRelationships id <$> Service.incomingRelationshipsAtRoot root id
  | .relationships (.related id) =>
      .relatedRelationships <$> Service.relatedRelationshipsAtRoot root id

private def exitCodeForResult : CommandResult → UInt8
  | .validation report => if report.ok then 0 else 4
  | _ => 0

private def writeFailure (format : OutputFormat) (command? : Option Command) (root : System.FilePath) (error : KnowledgeBaseError) : IO Unit := do
  let rendered := Render.renderFailure format command? root error
  match format with
  | .text => IO.eprintln rendered
  | .json => IO.println rendered

private def writeSuccess (format : OutputFormat) (command : Command) (root : System.FilePath) (result : CommandResult) : IO Unit :=
  IO.println <| Render.renderSuccess format command root result


def run (args : List String) : IO UInt8 := do
  match Parse.parseHelpTopic? args with
  | .error err =>
      let root ← resolveRootPath
      writeFailure .text none root err
      return err.exitCode
  | .ok (some topic) =>
      IO.println <| Render.renderHelp topic
      return 0
  | .ok none =>
      match Parse.parseArgs args with
      | .error err =>
          let root ← resolveRootPath
          writeFailure .text none root err
          return err.exitCode
      | .ok (global, command) =>
          let root ← resolveRootPath global.root?
          let result ← (dispatch root command).toIO'
          match result with
          | Except.ok result =>
              writeSuccess global.format command root result
              return exitCodeForResult result
          | Except.error err =>
              writeFailure global.format (some command) root err
              return err.exitCode


def main (args : List String) : IO Unit := do
  IO.Process.exit (← run args)

end Main
end Cli
end AFTK.KnowledgeBase
