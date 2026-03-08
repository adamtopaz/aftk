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


private def renderSections (sections : List (List String)) : String :=
  String.intercalate "\n\n" <| sections.map (String.intercalate "\n")

private def usageSection (usage : String) : List String :=
  ["Usage:", s!"  {usage}"]

private def titledSection (title : String) (lines : List String) : List String :=
  title :: lines

private def globalOptionsSection : List String :=
  titledSection "Global options:" [
    "  --root <path>         Use a specific knowledgebase root",
    "  --format text|json    Output format for command results",
    "  --help                Show this help text"
  ]

private def nodeKindValues : String :=
  String.intercalate ", " [
    "note", "definition", "theorem", "proofSketch",
    "example", "explanation", "concept", "documentation"
  ]

private def nodeStatusValues : String :=
  String.intercalate ", " ["draft", "active", "deprecated", "archived"]


def renderHelp : HelpTopic → String
  | .knowledgebase =>
      renderSections [
        usageSection "lake exe aftk knowledgebase [global-options] <command> ...",
        ["Manage the AFTK knowledge base."],
        globalOptionsSection,
        titledSection "Commands:" [
          "  init                  Initialize a knowledgebase root",
          "  status                Show root status",
          "  list                  List nodes",
          "  show                  Show a node",
          "  create                Create a node",
          "  rename                Rename a node",
          "  delete                Delete a node",
          "  body                  Show or replace node body content",
          "  metadata              Show, replace, or validate metadata",
          "  validate              Run validation",
          "  search                Search nodes",
          "  relationships         Inspect relationships"
        ],
        ["Run `lake exe aftk knowledgebase <command> --help` for detailed command help."]
      ]
  | .init =>
      renderSections [
        usageSection "lake exe aftk knowledgebase [global-options] init",
        ["Initialize a knowledgebase root."],
        globalOptionsSection
      ]
  | .status =>
      renderSections [
        usageSection "lake exe aftk knowledgebase [global-options] status",
        ["Show root status, manifest information, and internal directory presence."],
        globalOptionsSection
      ]
  | .list =>
      renderSections [
        usageSection "lake exe aftk knowledgebase [global-options] list [options]",
        ["List nodes from the knowledge base."],
        titledSection "Options:" [
          "  --prefix <prefix>     Restrict to node IDs under a dotted prefix",
          s!"  --kind <kind>         Restrict to a node kind ({nodeKindValues})",
          s!"  --status <status>     Restrict to a node status ({nodeStatusValues})",
          "  --tag <tag>           Restrict to nodes carrying an exact tag",
          "  --help                Show this help text"
        ],
        globalOptionsSection
      ]
  | .show =>
      renderSections [
        usageSection "lake exe aftk knowledgebase [global-options] show <id> [--body|--metadata|--paths]",
        ["Show a node's combined view, body, metadata, or canonical paths."],
        titledSection "Arguments:" [
          "  <id>                  Node identifier (example: topology.open_cover)"
        ],
        titledSection "Options:" [
          "  --body                Show only the Markdown body",
          "  --metadata            Show only the metadata JSON",
          "  --paths               Show only the canonical file paths",
          "  --help                Show this help text"
        ],
        globalOptionsSection
      ]
  | .create =>
      renderSections [
        usageSection "lake exe aftk knowledgebase [global-options] create <id> --title <title> [options]",
        ["Create a new node."],
        titledSection "Arguments:" [
          "  <id>                  Node identifier (example: topology.open_cover)"
        ],
        titledSection "Options:" [
          "  --title <title>       Required node title",
          s!"  --kind <kind>         Node kind (default: note; values: {nodeKindValues})",
          s!"  --status <status>     Node status (default: draft; values: {nodeStatusValues})",
          "  --summary <text>      Optional summary",
          "  --tag <tag>           Add a tag; may be repeated",
          "  --author <author>     Add an author; may be repeated",
          "  --body-file <path>    Initialize the body from a file",
          "  --body-stdin          Initialize the body from stdin",
          "  --help                Show this help text"
        ],
        globalOptionsSection
      ]
  | .rename =>
      renderSections [
        usageSection "lake exe aftk knowledgebase [global-options] rename <old-id> <new-id>",
        ["Rename an existing node."],
        titledSection "Arguments:" [
          "  <old-id>              Existing node identifier",
          "  <new-id>              New node identifier"
        ],
        titledSection "Options:" [
          "  --help                Show this help text"
        ],
        globalOptionsSection
      ]
  | .delete =>
      renderSections [
        usageSection "lake exe aftk knowledgebase [global-options] delete <id>",
        ["Delete a node's canonical Markdown and metadata files."],
        titledSection "Arguments:" [
          "  <id>                  Node identifier"
        ],
        titledSection "Options:" [
          "  --help                Show this help text"
        ],
        globalOptionsSection
      ]
  | .body =>
      renderSections [
        usageSection "lake exe aftk knowledgebase [global-options] body <subcommand> ...",
        ["Show or replace node body content."],
        titledSection "Subcommands:" [
          "  show                  Print the Markdown body for a node",
          "  set                   Replace the Markdown body for a node"
        ],
        globalOptionsSection,
        ["Run `lake exe aftk knowledgebase body <subcommand> --help` for detailed command help."]
      ]
  | .bodyShow =>
      renderSections [
        usageSection "lake exe aftk knowledgebase [global-options] body show <id>",
        ["Print the Markdown body for a node."],
        titledSection "Arguments:" [
          "  <id>                  Node identifier"
        ],
        titledSection "Options:" [
          "  --help                Show this help text"
        ],
        globalOptionsSection
      ]
  | .bodySet =>
      renderSections [
        usageSection "lake exe aftk knowledgebase [global-options] body set <id> (--from <path> | --stdin)",
        ["Replace the Markdown body for a node."],
        titledSection "Arguments:" [
          "  <id>                  Node identifier"
        ],
        titledSection "Options:" [
          "  --from <path>         Read the replacement body from a file",
          "  --stdin               Read the replacement body from stdin",
          "  --help                Show this help text"
        ],
        globalOptionsSection
      ]
  | .metadata =>
      renderSections [
        usageSection "lake exe aftk knowledgebase [global-options] metadata <subcommand> ...",
        ["Show, replace, or validate node metadata."],
        titledSection "Subcommands:" [
          "  show                  Print a node's metadata JSON",
          "  replace               Replace a node's metadata from JSON input",
          "  validate              Validate a node's metadata and related storage"
        ],
        globalOptionsSection,
        ["Run `lake exe aftk knowledgebase metadata <subcommand> --help` for detailed command help."]
      ]
  | .metadataShow =>
      renderSections [
        usageSection "lake exe aftk knowledgebase [global-options] metadata show <id>",
        ["Print a node's metadata JSON."],
        titledSection "Arguments:" [
          "  <id>                  Node identifier"
        ],
        titledSection "Options:" [
          "  --help                Show this help text"
        ],
        globalOptionsSection
      ]
  | .metadataReplace =>
      renderSections [
        usageSection "lake exe aftk knowledgebase [global-options] metadata replace <id> (--from <path> | --stdin)",
        ["Replace a node's metadata from JSON input."],
        titledSection "Arguments:" [
          "  <id>                  Node identifier"
        ],
        titledSection "Options:" [
          "  --from <path>         Read replacement metadata JSON from a file",
          "  --stdin               Read replacement metadata JSON from stdin",
          "  --help                Show this help text"
        ],
        globalOptionsSection
      ]
  | .metadataValidate =>
      renderSections [
        usageSection "lake exe aftk knowledgebase [global-options] metadata validate <id>",
        ["Validate a node's metadata and related storage invariants."],
        titledSection "Arguments:" [
          "  <id>                  Node identifier"
        ],
        titledSection "Options:" [
          "  --help                Show this help text"
        ],
        globalOptionsSection
      ]
  | .validate =>
      renderSections [
        usageSection "lake exe aftk knowledgebase [global-options] validate <subcommand>",
        ["Run validation at different scopes."],
        titledSection "Subcommands:" [
          "  storage               Validate storage structure without loading every node pair",
          "  node                  Validate a single node by ID",
          "  all                   Validate the full knowledgebase root"
        ],
        globalOptionsSection,
        ["Run `lake exe aftk knowledgebase validate <subcommand> --help` for detailed command help."]
      ]
  | .validateStorage =>
      renderSections [
        usageSection "lake exe aftk knowledgebase [global-options] validate storage",
        ["Validate storage-level root structure and required files."],
        titledSection "Options:" [
          "  --help                Show this help text"
        ],
        globalOptionsSection
      ]
  | .validateNode =>
      renderSections [
        usageSection "lake exe aftk knowledgebase [global-options] validate node <id>",
        ["Validate a single node by ID."],
        titledSection "Arguments:" [
          "  <id>                  Node identifier"
        ],
        titledSection "Options:" [
          "  --help                Show this help text"
        ],
        globalOptionsSection
      ]
  | .validateAll =>
      renderSections [
        usageSection "lake exe aftk knowledgebase [global-options] validate all",
        ["Validate the full knowledgebase root."],
        titledSection "Options:" [
          "  --help                Show this help text"
        ],
        globalOptionsSection
      ]
  | .search =>
      renderSections [
        usageSection "lake exe aftk knowledgebase [global-options] search <subcommand> ...",
        ["Search nodes by text or exact tag match."],
        titledSection "Subcommands:" [
          "  text                  Search title, summary, and body text",
          "  tag                   Search for an exact tag"
        ],
        globalOptionsSection,
        ["Run `lake exe aftk knowledgebase search <subcommand> --help` for detailed command help."]
      ]
  | .searchText =>
      renderSections [
        usageSection "lake exe aftk knowledgebase [global-options] search text <query> [--limit <n>]",
        ["Search title, summary, and body text using case-insensitive substring matching."],
        titledSection "Arguments:" [
          "  <query>               Query string"
        ],
        titledSection "Options:" [
          "  --limit <n>           Restrict the number of returned hits",
          "  --help                Show this help text"
        ],
        globalOptionsSection
      ]
  | .searchTag =>
      renderSections [
        usageSection "lake exe aftk knowledgebase [global-options] search tag <tag> [--limit <n>]",
        ["Search for nodes with an exact tag match."],
        titledSection "Arguments:" [
          "  <tag>                 Tag value"
        ],
        titledSection "Options:" [
          "  --limit <n>           Restrict the number of returned hits",
          "  --help                Show this help text"
        ],
        globalOptionsSection
      ]
  | .relationships =>
      renderSections [
        usageSection "lake exe aftk knowledgebase [global-options] relationships <subcommand> <id>",
        ["Inspect outgoing, incoming, or combined relationships for a node."],
        titledSection "Subcommands:" [
          "  outgoing              List relationships declared by the node",
          "  incoming              List relationships pointing to the node",
          "  related               Show both outgoing and incoming relationships"
        ],
        globalOptionsSection,
        ["Run `lake exe aftk knowledgebase relationships <subcommand> --help` for detailed command help."]
      ]
  | .relationshipsOutgoing =>
      renderSections [
        usageSection "lake exe aftk knowledgebase [global-options] relationships outgoing <id>",
        ["List relationships declared by the node."],
        titledSection "Arguments:" [
          "  <id>                  Node identifier"
        ],
        titledSection "Options:" [
          "  --help                Show this help text"
        ],
        globalOptionsSection
      ]
  | .relationshipsIncoming =>
      renderSections [
        usageSection "lake exe aftk knowledgebase [global-options] relationships incoming <id>",
        ["List relationships pointing to the node."],
        titledSection "Arguments:" [
          "  <id>                  Node identifier"
        ],
        titledSection "Options:" [
          "  --help                Show this help text"
        ],
        globalOptionsSection
      ]
  | .relationshipsRelated =>
      renderSections [
        usageSection "lake exe aftk knowledgebase [global-options] relationships related <id>",
        ["Show both outgoing and incoming relationships for a node."],
        titledSection "Arguments:" [
          "  <id>                  Node identifier"
        ],
        titledSection "Options:" [
          "  --help                Show this help text"
        ],
        globalOptionsSection
      ]


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
