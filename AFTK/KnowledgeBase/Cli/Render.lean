import AFTK.KnowledgeBase.Cli.Types
import AFTK.KnowledgeBase.Serialization

namespace AFTK.KnowledgeBase
namespace Cli
namespace Render

open Lean
open Validation

private def commandName : Command → String
  | .init => "init"
  | .status => "status"
  | .list _ => "list"
  | .show _ _ => "show"
  | .create _ _ => "create"
  | .rename _ _ => "rename"
  | .delete _ => "delete"
  | .body (.show _) => "body.show"
  | .body (.set _ _) => "body.set"
  | .metadata (.show _) => "metadata.show"
  | .metadata (.replace _ _) => "metadata.replace"
  | .metadata (.validate _) => "metadata.validate"
  | .validate .storage => "validate.storage"
  | .validate (.node _) => "validate.node"
  | .validate .all => "validate.all"
  | .search (.text _ _) => "search.text"
  | .search (.tag _ _) => "search.tag"
  | .relationships (.outgoing _) => "relationships.outgoing"
  | .relationships (.incoming _) => "relationships.incoming"
  | .relationships (.related _) => "relationships.related"

private def boolWord (b : Bool) : String := if b then "yes" else "no"

private def metadataLine (label value : String) : String :=
  s!"{label}: {value}"

private def renderMetadataText (metadata : NodeMetadata) : String :=
  Serialization.renderNodeMetadata metadata |>.trimAsciiEnd.toString

private def renderStoredNodeText (stored : StoredNode) : String :=
  let metadata := stored.node.metadata
  let header := [
    metadataLine "Node" metadata.id.value,
    metadataLine "Title" metadata.title,
    metadataLine "Kind" metadata.kind.asString,
    metadataLine "Status" metadata.status.asString
  ]
  let summary := match metadata.summary? with | some s => [metadataLine "Summary" s] | none => []
  let tags := if metadata.tags.isEmpty then [] else [metadataLine "Tags" (String.intercalate ", " metadata.tags.toList)]
  let authors := if metadata.authors.isEmpty then [] else [metadataLine "Authors" (String.intercalate ", " metadata.authors.toList)]
  let createdAt := match metadata.createdAt? with | some ts => [metadataLine "CreatedAt" ts.value] | none => []
  let updatedAt := match metadata.updatedAt? with | some ts => [metadataLine "UpdatedAt" ts.value] | none => []
  let paths := [
    metadataLine "MarkdownPath" stored.paths.markdownPath.toString,
    metadataLine "MetadataPath" stored.paths.metadataPath.toString
  ]
  let prelude := header ++ summary ++ tags ++ authors ++ createdAt ++ updatedAt ++ paths
  String.intercalate "\n" <| prelude ++ ["", "Body:", stored.node.body]

private def severityString : ValidationSeverity → String
  | .error => "error"
  | .warning => "warning"
  | .info => "info"

private def renderValidationText (report : ValidationReport) : String :=
  if report.issues.isEmpty then
    "Validation passed with no issues."
  else
    let summary := s!"Validation {(if report.ok then "completed" else "failed")} with {report.issues.size} issue(s)."
    let body := report.issues.toList.map fun issue =>
      let pathSuffix := match issue.path? with | some path => s!" [{path}]" | none => ""
      let relatedSuffix := match issue.relatedNodeId? with | some id => s!" (related: {id})" | none => ""
      s!"- {severityString issue.severity}: {issue.code}: {issue.message}{pathSuffix}{relatedSuffix}"
    String.intercalate "\n" (summary :: body)

private def renderSearchText (result : Search.SearchResult) : String :=
  if result.hits.isEmpty then
    "No matches."
  else
    String.intercalate "\n\n" <| result.hits.toList.map fun hit =>
      let title := hit.title?.map (fun t => s!" — {t}") |>.getD ""
      let scopes := if hit.matchedScopes.isEmpty then "" else s!" [{String.intercalate ", " (hit.matchedScopes.toList.map (fun s => match s with | .bodyText => "body" | .title => "title" | .summary => "summary" | .tags => "tags" | .metadata => "metadata" | .allText => "allText"))}]"
      let snippet := hit.snippet?.map (fun s => s!"\n  {s}") |>.getD ""
      s!"{hit.id}{title}{scopes}{snippet}"

private def renderOutgoingRelationshipsText (id : NodeId) (relationships : Array Relationship) : String :=
  if relationships.isEmpty then
    s!"No outgoing relationships for {id}."
  else
    let lines := relationships.toList.map fun rel =>
      let label := rel.label?.map (fun value => s!" — {value}") |>.getD ""
      s!"- {rel.kind.asString}: {rel.target}{label}"
    String.intercalate "\n" (s!"Outgoing relationships for {id}:" :: lines)

private def renderIncomingRelationshipsText (id : NodeId) (relationships : Array Search.IncomingRelationship) : String :=
  if relationships.isEmpty then
    s!"No incoming relationships for {id}."
  else
    let lines := relationships.toList.map fun edge =>
      let title := edge.sourceTitle?.map (fun value => s!" ({value})") |>.getD ""
      s!"- {edge.source}{title}: {edge.relationship.kind.asString}"
    String.intercalate "\n" (s!"Incoming relationships for {id}:" :: lines)

private def resultToJson : CommandResult → Json
  | .init paths => Json.mkObj [("paths", toJson paths)]
  | .status info => toJson info
  | .list nodes => Json.mkObj [("nodes", toJson nodes)]
  | .show stored => toJson stored
  | .body id body => Json.mkObj [("id", toJson id), ("body", toJson body)]
  | .metadata metadata => Json.mkObj [("metadata", toJson metadata)]
  | .paths id paths => Json.mkObj [("id", toJson id), ("paths", toJson paths)]
  | .create stored => toJson stored
  | .rename oldId stored => Json.mkObj [("oldId", toJson oldId), ("node", toJson stored)]
  | .delete id => Json.mkObj [("id", toJson id)]
  | .validation report => toJson report
  | .search result => toJson result
  | .outgoingRelationships id relationships => Json.mkObj [("id", toJson id), ("relationships", toJson relationships)]
  | .incomingRelationships id relationships => Json.mkObj [("id", toJson id), ("relationships", toJson relationships)]
  | .relatedRelationships result => toJson result

private def renderTextResult : CommandResult → String
  | .init paths => s!"Initialized knowledge base at {paths.rootDir}"
  | .status info =>
      String.intercalate "\n" [
        s!"Root: {info.root}",
        s!"Initialized: {boolWord info.initialized}",
        s!"SchemaVersion: {info.manifest.schemaVersion}",
        s!"ManifestKind: {info.manifest.kind}",
        s!"NodeCount: {info.nodeCount}",
        s!"InternalDirExists: {boolWord info.internalDirExists}",
        s!"IndexDirExists: {boolWord info.indexDirExists}",
        s!"CacheDirExists: {boolWord info.cacheDirExists}",
        s!"TmpDirExists: {boolWord info.tmpDirExists}"
      ]
  | .list nodes =>
      if nodes.isEmpty then
        "No nodes."
      else
        String.intercalate "\n" <| nodes.toList.map fun metadata =>
          s!"{metadata.id}\t{metadata.kind.asString}\t{metadata.status.asString}\t{metadata.title}"
  | .show stored => renderStoredNodeText stored
  | .body _ body => body
  | .metadata metadata => renderMetadataText metadata
  | .paths id paths => String.intercalate "\n" [
      s!"Node: {id}",
      s!"MarkdownPath: {paths.markdownPath}",
      s!"MetadataPath: {paths.metadataPath}"
    ]
  | .create stored => s!"Created node {stored.node.metadata.id}"
  | .rename oldId stored => s!"Renamed {oldId} to {stored.node.metadata.id}"
  | .delete id => s!"Deleted node {id}"
  | .validation report => renderValidationText report
  | .search result => renderSearchText result
  | .outgoingRelationships id relationships => renderOutgoingRelationshipsText id relationships
  | .incomingRelationships id relationships => renderIncomingRelationshipsText id relationships
  | .relatedRelationships result =>
      renderOutgoingRelationshipsText result.id result.outgoing ++ "\n\n" ++
      renderIncomingRelationshipsText result.id result.incoming


def renderSuccess (format : OutputFormat) (command : Command) (root : System.FilePath) (result : CommandResult) : String :=
  match format with
  | .text => renderTextResult result
  | .json =>
      Json.pretty <| Json.mkObj [
        ("command", Json.str (commandName command)),
        ("root", toJson root),
        ("ok", toJson true),
        ("result", resultToJson result),
        ("warnings", Json.arr #[])
      ]


def renderFailure (format : OutputFormat) (command? : Option Command) (root : System.FilePath) (error : KnowledgeBaseError) : String :=
  match format with
  | .text => s!"{error.code}: {error.message}"
  | .json =>
      let commandName := command?.map commandName |>.getD "unknown"
      Json.pretty <| Json.mkObj [
        ("command", Json.str commandName),
        ("root", toJson root),
        ("ok", toJson false),
        ("error", toJson ({ code := error.code, message := error.message } : CliError)),
        ("warnings", Json.arr #[])
      ]

end Render
end Cli
end AFTK.KnowledgeBase
