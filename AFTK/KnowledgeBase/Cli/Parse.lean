import AFTK.KnowledgeBase.Cli.Types

namespace AFTK.KnowledgeBase
namespace Cli
namespace Parse

private def usageError {α : Type} (message : String) : Except KnowledgeBaseError α :=
  throw <| KnowledgeBaseError.usage message

private def parseNodeId (raw : String) : Except KnowledgeBaseError NodeId :=
  match NodeId.ofString? raw with
  | .ok id => pure id
  | .error err => usageError s!"Invalid node id '{raw}': {err}"

private def parseNodeKind (raw : String) : Except KnowledgeBaseError NodeKind :=
  match NodeKind.ofString? raw with
  | .ok kind => pure kind
  | .error err => usageError err

private def parseNodeStatus (raw : String) : Except KnowledgeBaseError NodeStatus :=
  match NodeStatus.ofString? raw with
  | .ok status => pure status
  | .error err => usageError err

private def parseNat (raw : String) : Except KnowledgeBaseError Nat :=
  match raw.toNat? with
  | some n => pure n
  | none => usageError s!"Expected a natural number, got '{raw}'"

private def parseOutputFormat (raw : String) : Except KnowledgeBaseError OutputFormat :=
  match raw with
  | "text" => pure .text
  | "json" => pure .json
  | _ => usageError s!"Unknown output format '{raw}'; expected text or json"

private partial def parseGlobalOptionsAux (opts : GlobalOptions) : List String → Except KnowledgeBaseError (GlobalOptions × List String)
  | "--root" :: path :: rest => parseGlobalOptionsAux { opts with root? := some path } rest
  | "--root" :: [] => usageError "Missing value for --root"
  | "--format" :: format :: rest => do
      let format ← parseOutputFormat format
      parseGlobalOptionsAux { opts with format := format } rest
  | "--format" :: [] => usageError "Missing value for --format"
  | arg :: rest =>
      if arg.startsWith "--" then
        usageError s!"Unknown global option '{arg}'"
      else
        pure (opts, arg :: rest)
  | [] => pure (opts, [])

private def parseGlobalOptions (args : List String) : Except KnowledgeBaseError (GlobalOptions × List String) :=
  parseGlobalOptionsAux {} args

private partial def parseListOptionsAux (opts : ListOptions) : List String → Except KnowledgeBaseError ListOptions
  | [] => pure opts
  | "--prefix" :: pref :: rest => parseListOptionsAux { opts with prefix? := some pref } rest
  | "--prefix" :: [] => usageError "Missing value for --prefix"
  | "--kind" :: kind :: rest => do
      let kind ← parseNodeKind kind
      parseListOptionsAux { opts with kind? := some kind } rest
  | "--kind" :: [] => usageError "Missing value for --kind"
  | "--status" :: status :: rest => do
      let status ← parseNodeStatus status
      parseListOptionsAux { opts with status? := some status } rest
  | "--status" :: [] => usageError "Missing value for --status"
  | "--tag" :: tag :: rest => parseListOptionsAux { opts with tag? := some tag } rest
  | "--tag" :: [] => usageError "Missing value for --tag"
  | arg :: _ => usageError s!"Unknown list option '{arg}'"

private def parseListOptions (args : List String) : Except KnowledgeBaseError ListOptions :=
  parseListOptionsAux {} args

private partial def parseCreateOptionsAux
    (title? : Option String)
    (kind : NodeKind)
    (status : NodeStatus)
    (summary? : Option String)
    (tags : Array String)
    (authors : Array String)
    (bodySource? : Option InputSource) :
    List String → Except KnowledgeBaseError CreateOptions
  | [] =>
      match title? with
      | some title => pure {
          title := title
          kind := kind
          status := status
          summary? := summary?
          tags := tags
          authors := authors
          bodySource? := bodySource?
        }
      | none => usageError "create requires --title <title>"
  | "--title" :: title :: rest =>
      parseCreateOptionsAux (some title) kind status summary? tags authors bodySource? rest
  | "--title" :: [] => usageError "Missing value for --title"
  | "--kind" :: raw :: rest => do
      let kind ← parseNodeKind raw
      parseCreateOptionsAux title? kind status summary? tags authors bodySource? rest
  | "--kind" :: [] => usageError "Missing value for --kind"
  | "--status" :: raw :: rest => do
      let status ← parseNodeStatus raw
      parseCreateOptionsAux title? kind status summary? tags authors bodySource? rest
  | "--status" :: [] => usageError "Missing value for --status"
  | "--summary" :: summary :: rest =>
      parseCreateOptionsAux title? kind status (some summary) tags authors bodySource? rest
  | "--summary" :: [] => usageError "Missing value for --summary"
  | "--tag" :: tag :: rest =>
      parseCreateOptionsAux title? kind status summary? (tags.push tag) authors bodySource? rest
  | "--tag" :: [] => usageError "Missing value for --tag"
  | "--author" :: author :: rest =>
      parseCreateOptionsAux title? kind status summary? tags (authors.push author) bodySource? rest
  | "--author" :: [] => usageError "Missing value for --author"
  | "--body-file" :: path :: rest =>
      match bodySource? with
      | some _ => usageError "Specify only one of --body-file and --body-stdin"
      | none => parseCreateOptionsAux title? kind status summary? tags authors (some (.file path)) rest
  | "--body-file" :: [] => usageError "Missing value for --body-file"
  | "--body-stdin" :: rest =>
      match bodySource? with
      | some _ => usageError "Specify only one of --body-file and --body-stdin"
      | none => parseCreateOptionsAux title? kind status summary? tags authors (some .stdin) rest
  | arg :: _ => usageError s!"Unknown create option '{arg}'"

private def parseCreateOptions (args : List String) : Except KnowledgeBaseError CreateOptions :=
  parseCreateOptionsAux none .note .draft none #[] #[] none args

private def parseShowSelection (args : List String) : Except KnowledgeBaseError ShowSelection :=
  match args with
  | [] => pure .combined
  | ["--body"] => pure .body
  | ["--metadata"] => pure .metadata
  | ["--paths"] => pure .paths
  | arg :: _ => usageError s!"Unknown show option '{arg}'"

private def parseRequiredInputSource (name fileFlag stdinFlag : String) (args : List String) : Except KnowledgeBaseError InputSource :=
  match args with
  | [flag, path] =>
      if flag == fileFlag then pure (.file path) else usageError s!"Unknown option '{flag}' for {name}"
  | [flag] =>
      if flag == stdinFlag then pure .stdin else usageError s!"Unknown option '{flag}' for {name}"
  | [] => usageError s!"{name} requires either {fileFlag} <path> or {stdinFlag}"
  | arg :: _ => usageError s!"Unknown option '{arg}' for {name}"

private def parseSearchLimit (args : List String) : Except KnowledgeBaseError (Option Nat) :=
  match args with
  | [] => pure none
  | ["--limit", raw] => some <$> parseNat raw
  | [arg] => usageError s!"Unknown search option '{arg}'"
  | arg :: _ => usageError s!"Unknown search option '{arg}'"

private def parseCommand : List String → Except KnowledgeBaseError Command
  | [] => usageError "Expected a knowledgebase command"
  | "init" :: rest =>
      if rest.isEmpty then pure .init else usageError "init does not take positional arguments"
  | "status" :: rest =>
      if rest.isEmpty then pure .status else usageError "status does not take positional arguments"
  | "list" :: rest => do
      let opts ← parseListOptions rest
      pure <| .list opts
  | "show" :: id :: rest => do
      let id ← parseNodeId id
      let selection ← parseShowSelection rest
      pure <| .show id selection
  | "show" :: [] => usageError "show requires a node id"
  | "create" :: id :: rest => do
      let id ← parseNodeId id
      let opts ← parseCreateOptions rest
      pure <| .create id opts
  | "create" :: [] => usageError "create requires a node id"
  | "rename" :: oldId :: newId :: rest => do
      if rest.isEmpty then
        pure <| .rename (← parseNodeId oldId) (← parseNodeId newId)
      else
        usageError "rename takes exactly two node ids"
  | "rename" :: _ => usageError "rename requires <old-id> <new-id>"
  | "delete" :: id :: rest => do
      if rest.isEmpty then
        pure <| .delete (← parseNodeId id)
      else
        usageError "delete takes exactly one node id"
  | "delete" :: [] => usageError "delete requires a node id"
  | "body" :: "show" :: id :: rest => do
      if rest.isEmpty then
        pure <| .body (.show (← parseNodeId id))
      else
        usageError "body show takes exactly one node id"
  | "body" :: "show" :: [] => usageError "body show requires a node id"
  | "body" :: "set" :: id :: rest => do
      let id ← parseNodeId id
      let source ← parseRequiredInputSource "body set" "--from" "--stdin" rest
      pure <| .body (.set id source)
  | "body" :: "set" :: [] => usageError "body set requires a node id"
  | "body" :: cmd :: _ => usageError s!"Unknown body command '{cmd}'"
  | "body" :: [] => usageError "Expected a body subcommand"
  | "metadata" :: "show" :: id :: rest => do
      if rest.isEmpty then
        pure <| .metadata (.show (← parseNodeId id))
      else
        usageError "metadata show takes exactly one node id"
  | "metadata" :: "show" :: [] => usageError "metadata show requires a node id"
  | "metadata" :: "replace" :: id :: rest => do
      let id ← parseNodeId id
      let source ← parseRequiredInputSource "metadata replace" "--from" "--stdin" rest
      pure <| .metadata (.replace id source)
  | "metadata" :: "replace" :: [] => usageError "metadata replace requires a node id"
  | "metadata" :: "validate" :: id :: rest => do
      if rest.isEmpty then
        pure <| .metadata (.validate (← parseNodeId id))
      else
        usageError "metadata validate takes exactly one node id"
  | "metadata" :: "validate" :: [] => usageError "metadata validate requires a node id"
  | "metadata" :: cmd :: _ => usageError s!"Unknown metadata command '{cmd}'"
  | "metadata" :: [] => usageError "Expected a metadata subcommand"
  | "validate" :: "storage" :: rest =>
      if rest.isEmpty then pure <| .validate .storage else usageError "validate storage takes no further arguments"
  | "validate" :: "node" :: id :: rest => do
      if rest.isEmpty then
        pure <| .validate (.node (← parseNodeId id))
      else
        usageError "validate node takes exactly one node id"
  | "validate" :: "node" :: [] => usageError "validate node requires a node id"
  | "validate" :: "all" :: rest =>
      if rest.isEmpty then pure <| .validate .all else usageError "validate all takes no further arguments"
  | "validate" :: cmd :: _ => usageError s!"Unknown validate command '{cmd}'"
  | "validate" :: [] => usageError "Expected a validate subcommand"
  | "search" :: "text" :: query :: rest => do
      let limit? ← parseSearchLimit rest
      pure <| .search (.text query limit?)
  | "search" :: "text" :: [] => usageError "search text requires a query"
  | "search" :: "tag" :: tag :: rest => do
      let limit? ← parseSearchLimit rest
      pure <| .search (.tag tag limit?)
  | "search" :: "tag" :: [] => usageError "search tag requires a tag"
  | "search" :: cmd :: _ => usageError s!"Unknown search command '{cmd}'"
  | "search" :: [] => usageError "Expected a search subcommand"
  | "relationships" :: "outgoing" :: id :: rest => do
      if rest.isEmpty then
        pure <| .relationships (.outgoing (← parseNodeId id))
      else
        usageError "relationships outgoing takes exactly one node id"
  | "relationships" :: "outgoing" :: [] => usageError "relationships outgoing requires a node id"
  | "relationships" :: "incoming" :: id :: rest => do
      if rest.isEmpty then
        pure <| .relationships (.incoming (← parseNodeId id))
      else
        usageError "relationships incoming takes exactly one node id"
  | "relationships" :: "incoming" :: [] => usageError "relationships incoming requires a node id"
  | "relationships" :: "related" :: id :: rest => do
      if rest.isEmpty then
        pure <| .relationships (.related (← parseNodeId id))
      else
        usageError "relationships related takes exactly one node id"
  | "relationships" :: "related" :: [] => usageError "relationships related requires a node id"
  | "relationships" :: cmd :: _ => usageError s!"Unknown relationships command '{cmd}'"
  | "relationships" :: [] => usageError "Expected a relationships subcommand"
  | cmd :: _ => usageError s!"Unknown knowledgebase command '{cmd}'"


def parseArgs (args : List String) : Except KnowledgeBaseError (GlobalOptions × Command) := do
  let (global, rest) ← parseGlobalOptions args
  let command ← parseCommand rest
  pure (global, command)

end Parse
end Cli
end AFTK.KnowledgeBase
