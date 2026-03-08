import AFTK.KnowledgeBase.Cli.Parse
import AFTK.KnowledgeBase.Cli.Render
import AFTK.KnowledgeBase.Storage

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

private def statusInfoForRoot (root : System.FilePath) : KBIO StatusInfo := do
  let provisional := storagePathsForRoot root
  if !(← liftIO <| provisional.rootDir.pathExists) || !(← liftIO <| provisional.manifestPath.pathExists) then
    let internalDirExists ← liftIO <| provisional.internalDir.pathExists
    let indexDirExists ← liftIO <| provisional.indexDir.pathExists
    let cacheDirExists ← liftIO <| provisional.cacheDir.pathExists
    let tmpDirExists ← liftIO <| provisional.tmpDir.pathExists
    return {
      root := root
      manifest := defaultManifest
      initialized := false
      nodeCount := 0
      internalDirExists := internalDirExists
      indexDirExists := indexDirExists
      cacheDirExists := cacheDirExists
      tmpDirExists := tmpDirExists
    }
  let (paths, manifest) ← Storage.resolveInitializedRoot root
  let discovered ← Storage.scanCanonicalNodeFiles paths
  let nodeCount := discovered.foldl (init := 0) fun count files =>
    if files.markdownPath?.isSome && files.metadataPath?.isSome then count + 1 else count
  let internalDirExists ← liftIO <| paths.internalDir.pathExists
  let indexDirExists ← liftIO <| paths.indexDir.pathExists
  let cacheDirExists ← liftIO <| paths.cacheDir.pathExists
  let tmpDirExists ← liftIO <| paths.tmpDir.pathExists
  return {
    root := root
    manifest := manifest
    initialized := true
    nodeCount := nodeCount
    internalDirExists := internalDirExists
    indexDirExists := indexDirExists
    cacheDirExists := cacheDirExists
    tmpDirExists := tmpDirExists
  }

private def requireInitialized (root : System.FilePath) : KBIO (KnowledgeBaseStoragePaths × StorageManifest) :=
  Storage.resolveInitializedRoot root

private def filterListNodes (nodes : Array NodeMetadata) (opts : ListOptions) : Array NodeMetadata :=
  nodes.filter fun metadata =>
    let prefixOk := match opts.prefix? with
      | some pref => NodeId.startsWithSegmentPrefix metadata.id pref
      | none => true
    let kindOk := match opts.kind? with | some kind => metadata.kind == kind | none => true
    let statusOk := match opts.status? with | some status => metadata.status == status | none => true
    let tagOk := match opts.tag? with | some tag => metadata.tags.contains tag | none => true
    prefixOk && kindOk && statusOk && tagOk

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
      CommandResult.init <$> Storage.initRoot root
  | .status =>
      CommandResult.status <$> statusInfoForRoot root
  | .list opts => do
      let (paths, _) ← requireInitialized root
      let metadata ← Storage.loadAllMetadata paths
      pure <| .list (filterListNodes metadata opts)
  | .show id .combined => do
      let (paths, _) ← requireInitialized root
      .show <$> Storage.loadStoredNode paths id
  | .show id .body => do
      let (paths, _) ← requireInitialized root
      let stored ← Storage.loadStoredNode paths id
      pure <| .body id stored.node.body
  | .show id .metadata => do
      let (paths, _) ← requireInitialized root
      let stored ← Storage.loadStoredNode paths id
      pure <| .metadata stored.node.metadata
  | .show id .paths => do
      let (paths, _) ← requireInitialized root
      let _ ← Storage.loadStoredNode paths id
      pure <| .paths id (nodePaths paths id)
  | .create id opts => do
      let (paths, _) ← requireInitialized root
      let body ← liftIO <| loadBodyInput opts.bodySource?
      .create <$> Storage.createNode paths id opts.title body opts.kind opts.status opts.summary? opts.tags opts.authors
  | .rename oldId newId => do
      let (paths, _) ← requireInitialized root
      .rename oldId <$> Storage.renameNode paths oldId newId
  | .delete id => do
      let (paths, _) ← requireInitialized root
      Storage.deleteNode paths id
      pure <| .delete id
  | .body (.show id) => do
      let (paths, _) ← requireInitialized root
      let stored ← Storage.loadStoredNode paths id
      pure <| .body id stored.node.body
  | .body (.set id source) => do
      let (paths, _) ← requireInitialized root
      let body ← liftIO <| readInputSource source
      .show <$> Storage.setNodeBody paths id body
  | .metadata (.show id) => do
      let (paths, _) ← requireInitialized root
      let stored ← Storage.loadStoredNode paths id
      pure <| .metadata stored.node.metadata
  | .metadata (.replace id source) => do
      let (paths, _) ← requireInitialized root
      let metadata ← loadMetadataReplacement source
      .show <$> Storage.replaceNodeMetadata paths id metadata
  | .metadata (.validate id) =>
      return .validation (← liftIO <| Validation.validateMetadata root id)
  | .validate .storage =>
      return .validation (← liftIO <| Validation.validateStorage root)
  | .validate (.node id) =>
      return .validation (← liftIO <| Validation.validateNode root id)
  | .validate .all =>
      return .validation (← liftIO <| Validation.validateAll root)
  | .search (.text query limit?) => do
      let (paths, _) ← requireInitialized root
      .search <$> Search.searchText paths query limit?
  | .search (.tag tag limit?) => do
      let (paths, _) ← requireInitialized root
      .search <$> Search.searchTag paths tag limit?
  | .relationships (.outgoing id) => do
      let (paths, _) ← requireInitialized root
      .outgoingRelationships id <$> Search.outgoingRelationships paths id
  | .relationships (.incoming id) => do
      let (paths, _) ← requireInitialized root
      .incomingRelationships id <$> Search.incomingRelationships paths id
  | .relationships (.related id) => do
      let (paths, _) ← requireInitialized root
      .relatedRelationships <$> Search.relatedRelationships paths id

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
