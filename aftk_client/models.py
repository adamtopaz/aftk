from __future__ import annotations

from typing import Annotated, Any

from pydantic import BaseModel, ConfigDict, Field


PositiveInt = Annotated[int, Field(ge=1)]
NonEmptyStringList = Annotated[list[str], Field(min_length=1)]


class RequestModel(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)


class ResponseModel(BaseModel):
    model_config = ConfigDict(extra="ignore", populate_by_name=True)


class SourcePosition(ResponseModel):
    line: PositiveInt
    col: PositiveInt


class SourceRange(ResponseModel):
    start: SourcePosition
    stop: SourcePosition


class HoverResult(ResponseModel):
    text: str
    range: SourceRange | None = None


class PlainGoalResult(ResponseModel):
    goals: list[str]
    rendered: str


class PlainTermGoalResult(ResponseModel):
    goal: str
    range: SourceRange | None = None


class InfoViewResult(ResponseModel):
    hover: HoverResult | None = None
    plain_goal: PlainGoalResult | None = Field(default=None, alias="plainGoal")
    plain_term_goal: PlainTermGoalResult | None = Field(default=None, alias="plainTermGoal")


class LoadNodeResult(ResponseModel):
    ids: list[str] = Field(alias="id")


class GetGoalsResult(ResponseModel):
    goals: list[str]


class RunTacticResult(ResponseModel):
    goals: list[str]
    next_id: str = Field(alias="nextId")


class RunTacticStepsResult(ResponseModel):
    results: list[RunTacticResult]


class OpenResult(ResponseModel):
    path: str
    opened: bool


class CloseResult(ResponseModel):
    path: str
    closed: bool


class ShutdownResult(ResponseModel):
    stopped: int


class StorageManifest(ResponseModel):
    schema_version: int = Field(alias="schemaVersion")
    kind: str
    nodes_dir: str = Field(alias="nodesDir")
    internal_dir: str = Field(alias="internalDir")


class KnowledgeBaseStoragePaths(ResponseModel):
    root_dir: str = Field(alias="rootDir")
    manifest_path: str = Field(alias="manifestPath")
    nodes_dir: str = Field(alias="nodesDir")
    internal_dir: str = Field(alias="internalDir")
    index_dir: str = Field(alias="indexDir")
    cache_dir: str = Field(alias="cacheDir")
    tmp_dir: str = Field(alias="tmpDir")


class Relationship(ResponseModel):
    kind: str
    target: str
    label: str | None = None
    note: str | None = None


class LeanDeclRef(ResponseModel):
    module: str | None = None
    declaration: str
    kind: str | None = None


class NodeMetadata(ResponseModel):
    schema_version: int = Field(alias="schemaVersion")
    id: str
    title: str
    kind: str = "note"
    status: str = "draft"
    summary: str | None = None
    tags: list[str] = Field(default_factory=list)
    authors: list[str] = Field(default_factory=list)
    created_at: str | None = Field(default=None, alias="createdAt")
    updated_at: str | None = Field(default=None, alias="updatedAt")
    relationships: list[Relationship] = Field(default_factory=list)
    lean_refs: list[LeanDeclRef] = Field(default_factory=list, alias="leanRefs")


class KnowledgeBaseNode(ResponseModel):
    metadata: NodeMetadata
    body: str


class NodePaths(ResponseModel):
    markdown_path: str = Field(alias="markdownPath")
    metadata_path: str = Field(alias="metadataPath")


class StoredNode(ResponseModel):
    node: KnowledgeBaseNode
    paths: NodePaths


class SearchHit(ResponseModel):
    id: str
    score: float | None = None
    title: str | None = None
    summary: str | None = None
    matched_scopes: list[str] = Field(default_factory=list, alias="matchedScopes")
    snippet: str | None = None


class SearchResult(ResponseModel):
    hits: list[SearchHit] = Field(default_factory=list)


class IncomingRelationship(ResponseModel):
    source: str
    source_title: str | None = Field(default=None, alias="sourceTitle")
    relationship: Relationship


class RelatedRelationships(ResponseModel):
    id: str
    outgoing: list[Relationship] = Field(default_factory=list)
    incoming: list[IncomingRelationship] = Field(default_factory=list)


class ValidationScope(ResponseModel):
    kind: str
    id: str | None = None


class ValidationIssue(ResponseModel):
    code: str
    severity: str
    scope: ValidationScope
    message: str
    path: str | None = None
    related_node_id: str | None = Field(default=None, alias="relatedNodeId")


class ValidationReport(ResponseModel):
    ok: bool
    issues: list[ValidationIssue] = Field(default_factory=list)


class KnowledgeBaseStatusResult(ResponseModel):
    root: str
    manifest: StorageManifest
    initialized: bool
    node_count: int = Field(alias="nodeCount")
    internal_dir_exists: bool = Field(alias="internalDirExists")
    index_dir_exists: bool = Field(alias="indexDirExists")
    cache_dir_exists: bool = Field(alias="cacheDirExists")
    tmp_dir_exists: bool = Field(alias="tmpDirExists")


class KnowledgeBaseListResult(ResponseModel):
    nodes: list[NodeMetadata] = Field(default_factory=list)


class KnowledgeBaseBodyResult(ResponseModel):
    id: str
    body: str


class KnowledgeBasePathsResult(ResponseModel):
    id: str
    paths: NodePaths


class KnowledgeBaseRenameResult(ResponseModel):
    old_id: str = Field(alias="oldId")
    stored: StoredNode


class KnowledgeBaseDeleteResult(ResponseModel):
    id: str
    deleted: bool


class KnowledgeBaseOutgoingRelationshipsResult(ResponseModel):
    id: str
    relationships: list[Relationship] = Field(default_factory=list)


class KnowledgeBaseIncomingRelationshipsResult(ResponseModel):
    id: str
    relationships: list[IncomingRelationship] = Field(default_factory=list)


class InformalStatusResult(ResponseModel):
    tracked_declarations: int = Field(alias="trackedDeclarations")
    tracked_references: int = Field(alias="trackedReferences")
    declarations_with_multiple_references: int = Field(alias="declarationsWithMultipleReferences")


class InformalDeclDto(ResponseModel):
    decl_name: str = Field(alias="declName")
    refs: list[str] = Field(default_factory=list)
    ref_count: int = Field(alias="refCount")


class InformalRefDto(ResponseModel):
    ref: str
    decl_names: list[str] = Field(default_factory=list, alias="declNames")
    decl_count: int = Field(alias="declCount")


class InformalDeclDependencyDto(ResponseModel):
    decl_name: str = Field(alias="declName")
    dependencies: list[str] = Field(default_factory=list)


class InformalRefDependencyDto(ResponseModel):
    ref: str
    dependencies: list[str] = Field(default_factory=list)


class InformalDeclsResult(ResponseModel):
    entries: list[InformalDeclDto] = Field(default_factory=list)


class InformalDeclResult(ResponseModel):
    entry: InformalDeclDto


class InformalRefsResult(ResponseModel):
    entries: list[InformalRefDto] = Field(default_factory=list)


class InformalRefResult(ResponseModel):
    entry: InformalRefDto


class InformalDeclDepsResult(ResponseModel):
    rows: list[InformalDeclDependencyDto] = Field(default_factory=list)
    leaves: list[str] = Field(default_factory=list)


class InformalRefDepsResult(ResponseModel):
    rows: list[InformalRefDependencyDto] = Field(default_factory=list)
    leaves: list[str] = Field(default_factory=list)


class InformalPresentationSummary(ResponseModel):
    ref: str
    title: str
    kind: str | None = None
    status: str | None = None
    summary: str | None = None


class InformalBodyPresentation(ResponseModel):
    kind: str
    truncated: bool | None = None
    text: str | None = None


class InformalPresentationPayload(ResponseModel):
    summary: InformalPresentationSummary
    tags: list[str] = Field(default_factory=list)
    authors: list[str] = Field(default_factory=list)
    relationship_lines: list[str] = Field(default_factory=list, alias="relationshipLines")
    lean_ref_lines: list[str] = Field(default_factory=list, alias="leanRefLines")
    body: InformalBodyPresentation


class InformalPresentResult(ResponseModel):
    mode: str
    summary: InformalPresentationSummary
    payload: InformalPresentationPayload | None = None
    body_mode: str | None = Field(default=None, alias="bodyMode")


class OpenParams(RequestModel):
    path: str


class CloseParams(RequestModel):
    path: str


class FileLocationParams(RequestModel):
    path: str
    line: PositiveInt
    col: PositiveInt


class FileNodeParams(RequestModel):
    path: str
    node_id: str = Field(alias="id")


class RunTacticParams(RequestModel):
    path: str
    node_id: str = Field(alias="id")
    tactic: str


class RunTacticStepsParams(RequestModel):
    path: str
    node_id: str = Field(alias="id")
    tactics: NonEmptyStringList


class ShutdownParams(RequestModel):
    pass


class KnowledgeBaseRootParams(RequestModel):
    root: str | None = None


class KnowledgeBaseNodeParams(RequestModel):
    root: str | None = None
    id: str


class KnowledgeBaseListParams(RequestModel):
    root: str | None = None
    prefix: str | None = None
    kind: str | None = None
    status: str | None = None
    tag: str | None = None


class KnowledgeBaseCreateParams(RequestModel):
    root: str | None = None
    id: str
    title: str
    body: str | None = None
    kind: str | None = None
    status: str | None = None
    summary: str | None = None
    tags: list[str] | None = None
    authors: list[str] | None = None


class KnowledgeBaseRenameParams(RequestModel):
    root: str | None = None
    old_id: str = Field(alias="oldId")
    new_id: str = Field(alias="newId")


class KnowledgeBaseSetBodyParams(RequestModel):
    root: str | None = None
    id: str
    body: str


class KnowledgeBaseReplaceMetadataParams(RequestModel):
    root: str | None = None
    id: str
    metadata: dict[str, Any]


class KnowledgeBaseSearchTextParams(RequestModel):
    root: str | None = None
    query: str
    limit: int | None = None


class KnowledgeBaseSearchTagParams(RequestModel):
    root: str | None = None
    tag: str
    limit: int | None = None


class InformalModulesParams(RequestModel):
    modules: NonEmptyStringList


class InformalDeclsParams(RequestModel):
    modules: NonEmptyStringList
    prefix: str | None = None
    ref: str | None = None


class InformalDeclParams(RequestModel):
    modules: NonEmptyStringList
    decl_name: str = Field(alias="declName")


class InformalRefsParams(RequestModel):
    modules: NonEmptyStringList
    prefix: str | None = None


class InformalRefParams(RequestModel):
    modules: NonEmptyStringList
    ref: str


class InformalDepsParams(RequestModel):
    modules: NonEmptyStringList
    only_leaves: bool | None = Field(default=None, alias="onlyLeaves")


class InformalPresentParams(RequestModel):
    root: str | None = None
    ref: str
    mode: str | None = None
    body_mode: str | None = Field(default=None, alias="bodyMode")
