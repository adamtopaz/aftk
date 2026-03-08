module

public import AFTK.KnowledgeBase.Search
public import AFTK.KnowledgeBase.Validation

public section


namespace AFTK.KnowledgeBase
namespace Cli

open Lean

inductive OutputFormat
  | text
  | json
  deriving Repr, DecidableEq, Inhabited

inductive InputSource
  | stdin
  | file (path : System.FilePath)
  deriving Repr, DecidableEq, Inhabited

inductive ShowSelection
  | combined
  | body
  | metadata
  | paths
  deriving Repr, DecidableEq, Inhabited

structure GlobalOptions where
  root? : Option System.FilePath := none
  format : OutputFormat := .text
  deriving Repr, DecidableEq, Inhabited

structure ListOptions where
  prefix? : Option String := none
  kind? : Option NodeKind := none
  status? : Option NodeStatus := none
  tag? : Option String := none
  deriving Repr, DecidableEq, Inhabited

structure CreateOptions where
  title : String
  kind : NodeKind := .note
  status : NodeStatus := .draft
  summary? : Option String := none
  tags : Array String := #[]
  authors : Array String := #[]
  bodySource? : Option InputSource := none
  deriving Repr, DecidableEq

inductive BodyCommand
  | show (id : NodeId)
  | set (id : NodeId) (source : InputSource)
  deriving Repr, DecidableEq

inductive MetadataCommand
  | show (id : NodeId)
  | replace (id : NodeId) (source : InputSource)
  | validate (id : NodeId)
  deriving Repr, DecidableEq

inductive ValidateCommand
  | storage
  | node (id : NodeId)
  | all
  deriving Repr, DecidableEq

inductive SearchCommand
  | text (query : String) (limit? : Option Nat := none)
  | tag (tag : String) (limit? : Option Nat := none)
  deriving Repr, DecidableEq

inductive RelationshipCommand
  | outgoing (id : NodeId)
  | incoming (id : NodeId)
  | related (id : NodeId)
  deriving Repr, DecidableEq

inductive Command
  | init
  | status
  | list (opts : ListOptions := {})
  | show (id : NodeId) (selection : ShowSelection := .combined)
  | create (id : NodeId) (opts : CreateOptions)
  | rename (oldId : NodeId) (newId : NodeId)
  | delete (id : NodeId)
  | body (cmd : BodyCommand)
  | metadata (cmd : MetadataCommand)
  | validate (cmd : ValidateCommand)
  | search (cmd : SearchCommand)
  | relationships (cmd : RelationshipCommand)
  deriving Repr, DecidableEq

inductive HelpTopic
  | knowledgebase
  | init
  | status
  | list
  | show
  | create
  | rename
  | delete
  | body
  | bodyShow
  | bodySet
  | metadata
  | metadataShow
  | metadataReplace
  | metadataValidate
  | validate
  | validateStorage
  | validateNode
  | validateAll
  | search
  | searchText
  | searchTag
  | relationships
  | relationshipsOutgoing
  | relationshipsIncoming
  | relationshipsRelated
  deriving Repr, DecidableEq, Inhabited

structure CliWarning where
  code : String
  message : String
  deriving Repr, DecidableEq, Inhabited

instance : ToJson CliWarning where
  toJson warning := Json.mkObj [
    ("code", toJson warning.code),
    ("message", toJson warning.message)
  ]

structure CliError where
  code : String
  message : String
  deriving Repr, DecidableEq, Inhabited

instance : ToJson CliError where
  toJson err := Json.mkObj [
    ("code", toJson err.code),
    ("message", toJson err.message)
  ]

structure StatusInfo where
  root : System.FilePath
  manifest : StorageManifest
  initialized : Bool
  nodeCount : Nat
  internalDirExists : Bool
  indexDirExists : Bool
  cacheDirExists : Bool
  tmpDirExists : Bool
  deriving Repr, DecidableEq

instance : ToJson StatusInfo where
  toJson info := Json.mkObj [
    ("root", toJson info.root),
    ("manifest", toJson info.manifest),
    ("initialized", toJson info.initialized),
    ("nodeCount", toJson info.nodeCount),
    ("internalDirExists", toJson info.internalDirExists),
    ("indexDirExists", toJson info.indexDirExists),
    ("cacheDirExists", toJson info.cacheDirExists),
    ("tmpDirExists", toJson info.tmpDirExists)
  ]

inductive CommandResult
  | init (paths : KnowledgeBaseStoragePaths)
  | status (info : StatusInfo)
  | list (nodes : Array NodeMetadata)
  | show (stored : StoredNode)
  | body (id : NodeId) (body : String)
  | metadata (metadata : NodeMetadata)
  | paths (id : NodeId) (paths : NodePaths)
  | create (stored : StoredNode)
  | rename (oldId : NodeId) (stored : StoredNode)
  | delete (id : NodeId)
  | validation (report : Validation.ValidationReport)
  | search (result : Search.SearchResult)
  | outgoingRelationships (id : NodeId) (relationships : Array Relationship)
  | incomingRelationships (id : NodeId) (relationships : Array Search.IncomingRelationship)
  | relatedRelationships (result : Search.RelatedRelationships)
  deriving Repr

end Cli
end AFTK.KnowledgeBase
