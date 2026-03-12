from __future__ import annotations

from collections.abc import Callable
from typing import Any

from pydantic import BaseModel
from pydantic_ai.toolsets import CombinedToolset, FunctionToolset, WrapperToolset

from aftk import AsyncAftkClient
from aftk.errors import AftkClientError
from aftk.models import (
    CloseResult,
    GetGoalsResult,
    HoverResult,
    InfoViewResult,
    InformalDeclDepsResult,
    InformalDeclResult,
    InformalDeclsResult,
    InformalPresentResult,
    InformalRefDepsResult,
    InformalRefResult,
    InformalRefsResult,
    InformalStatusResult,
    KnowledgeBaseBodyResult,
    KnowledgeBaseDeleteResult,
    KnowledgeBaseIncomingRelationshipsResult,
    KnowledgeBaseListResult,
    KnowledgeBaseOutgoingRelationshipsResult,
    KnowledgeBasePathsResult,
    KnowledgeBaseRenameResult,
    KnowledgeBaseStatusResult,
    KnowledgeBaseStoragePaths,
    LoadNodeResult,
    NodeMetadata,
    OpenResult,
    PlainGoalResult,
    PlainTermGoalResult,
    RelatedRelationships,
    RunTacticResult,
    RunTacticStepsResult,
    SearchResult,
    StoredNode,
    ValidationReport,
)

from .errors import AftkToolkitExecutionError, failure_from_exception
from .models import (
    AftkToolFailure,
    AftkToolSuccess,
    InformalDependenciesInput,
    InformalGetDeclInput,
    InformalGetRefInput,
    InformalListDeclsInput,
    InformalListRefsInput,
    InformalModulesInput,
    InformalPresentInput,
    KnowledgeBaseCreateNodeInput,
    KnowledgeBaseListNodesInput,
    KnowledgeBaseNodeInput,
    KnowledgeBasePatchMetadataInput,
    KnowledgeBaseRenameNodeInput,
    KnowledgeBaseReplaceMetadataRawInput,
    KnowledgeBaseRootInput,
    KnowledgeBaseSearchTagInput,
    KnowledgeBaseSearchTextInput,
    KnowledgeBaseSetBodyInput,
    LeanLocationInput,
    LeanNodeInput,
    LeanNodeTacticInput,
    LeanNodeTacticStepsInput,
    LeanPathInput,
    LeanTacticAtInput,
    LeanTacticStepsAtInput,
)


class AftkToolkit(WrapperToolset[Any]):
    """Pydantic AI toolset exposing AFTK client operations to agents."""

    def __init__(
        self,
        client: AsyncAftkClient,
        *,
        include_lean: bool = True,
        include_knowledgebase: bool = True,
        include_informal: bool = True,
        read_only: bool = False,
        advanced: bool = False,
        close_client_on_exit: bool = False,
        id: str | None = None,
    ) -> None:
        self._client = client
        self._include_lean = include_lean
        self._include_knowledgebase = include_knowledgebase
        self._include_informal = include_informal
        self._read_only = read_only
        self._advanced = advanced
        self._close_client_on_exit = close_client_on_exit
        self._id = id
        self.wrapped = self._build_wrapped_toolset()

    @property
    def id(self) -> str | None:
        return self._id

    async def __aexit__(self, *args: Any) -> bool | None:
        try:
            return await self.wrapped.__aexit__(*args)
        finally:
            if self._close_client_on_exit:
                await self._client.aclose()

    async def call_tool(self, name: str, tool_args: dict[str, Any], ctx: Any, tool: Any) -> Any:
        try:
            result = await self.wrapped.call_tool(name, tool_args, ctx, tool)
        except (AftkClientError, AftkToolkitExecutionError) as exc:
            return failure_from_exception(name, exc)

        if isinstance(result, (AftkToolSuccess, AftkToolFailure)):
            return result
        return AftkToolSuccess(tool=name, data=self._normalize_result(result))

    def apply(self, visitor: Callable[[Any], None]) -> None:
        self.wrapped.apply(visitor)

    def visit_and_replace(self, visitor: Callable[[Any], Any]) -> Any:
        clone = self.__class__(
            self._client,
            include_lean=self._include_lean,
            include_knowledgebase=self._include_knowledgebase,
            include_informal=self._include_informal,
            read_only=self._read_only,
            advanced=self._advanced,
            close_client_on_exit=self._close_client_on_exit,
            id=self._id,
        )
        clone.wrapped = self.wrapped.visit_and_replace(visitor)
        return clone

    def _build_wrapped_toolset(self) -> CombinedToolset[Any]:
        toolsets: list[FunctionToolset[Any]] = []

        if self._include_lean:
            toolsets.append(self._build_lean_basic_toolset())
            if self._advanced:
                toolsets.append(self._build_lean_advanced_toolset())

        if self._include_knowledgebase:
            toolsets.append(self._build_kb_read_toolset())
            if not self._read_only:
                toolsets.append(self._build_kb_write_toolset())
            if self._advanced:
                toolsets.append(self._build_kb_advanced_read_toolset())
                if not self._read_only:
                    toolsets.append(self._build_kb_advanced_write_toolset())

        if self._include_informal:
            toolsets.append(self._build_informal_toolset())

        return CombinedToolset(toolsets=toolsets)

    def _build_lean_basic_toolset(self) -> FunctionToolset[Any]:
        toolset = self._new_function_toolset(layer="lean", suffix="lean-basic")
        self._register(toolset, self._lean_get_hover, name="lean_get_hover", mutates=False, advanced=False)
        self._register(toolset, self._lean_get_plain_goal, name="lean_get_plain_goal", mutates=False, advanced=False)
        self._register(
            toolset,
            self._lean_get_plain_term_goal,
            name="lean_get_plain_term_goal",
            mutates=False,
            advanced=False,
        )
        self._register(toolset, self._lean_get_infoview, name="lean_get_infoview", mutates=False, advanced=False)
        self._register(toolset, self._lean_get_goals_at, name="lean_get_goals_at", mutates=False, advanced=False)
        self._register(toolset, self._lean_run_tactic_at, name="lean_run_tactic_at", mutates=True, advanced=False)
        self._register(
            toolset,
            self._lean_run_tactic_steps_at,
            name="lean_run_tactic_steps_at",
            mutates=True,
            advanced=False,
        )
        return toolset

    def _build_lean_advanced_toolset(self) -> FunctionToolset[Any]:
        toolset = self._new_function_toolset(layer="lean", suffix="lean-advanced")
        self._register(toolset, self._lean_open_file, name="lean_open_file", mutates=False, advanced=True)
        self._register(toolset, self._lean_close_file, name="lean_close_file", mutates=False, advanced=True)
        self._register(toolset, self._lean_load_node, name="lean_load_node", mutates=False, advanced=True)
        self._register(toolset, self._lean_get_goals, name="lean_get_goals", mutates=False, advanced=True)
        self._register(toolset, self._lean_run_tactic, name="lean_run_tactic", mutates=True, advanced=True)
        self._register(
            toolset,
            self._lean_run_tactic_steps,
            name="lean_run_tactic_steps",
            mutates=True,
            advanced=True,
        )
        return toolset

    def _build_kb_read_toolset(self) -> FunctionToolset[Any]:
        toolset = self._new_function_toolset(layer="knowledgebase", suffix="kb-read")
        self._register(toolset, self._kb_status, name="kb_status", mutates=False, advanced=False)
        self._register(toolset, self._kb_list_nodes, name="kb_list_nodes", mutates=False, advanced=False)
        self._register(toolset, self._kb_show_node, name="kb_show_node", mutates=False, advanced=False)
        self._register(toolset, self._kb_get_body, name="kb_get_body", mutates=False, advanced=False)
        self._register(toolset, self._kb_search_text, name="kb_search_text", mutates=False, advanced=False)
        self._register(toolset, self._kb_search_tag, name="kb_search_tag", mutates=False, advanced=False)
        self._register(toolset, self._kb_related, name="kb_related", mutates=False, advanced=False)
        self._register(toolset, self._kb_validate_node, name="kb_validate_node", mutates=False, advanced=False)
        self._register(toolset, self._kb_validate_all, name="kb_validate_all", mutates=False, advanced=False)
        return toolset

    def _build_kb_write_toolset(self) -> FunctionToolset[Any]:
        toolset = self._new_function_toolset(layer="knowledgebase", suffix="kb-write")
        self._register(toolset, self._kb_create_node, name="kb_create_node", mutates=True, advanced=False)
        self._register(toolset, self._kb_set_body, name="kb_set_body", mutates=True, advanced=False)
        self._register(toolset, self._kb_patch_metadata, name="kb_patch_metadata", mutates=True, advanced=False)
        self._register(toolset, self._kb_rename_node, name="kb_rename_node", mutates=True, advanced=False)
        self._register(toolset, self._kb_delete_node, name="kb_delete_node", mutates=True, advanced=False)
        return toolset

    def _build_kb_advanced_read_toolset(self) -> FunctionToolset[Any]:
        toolset = self._new_function_toolset(layer="knowledgebase", suffix="kb-advanced-read")
        self._register(toolset, self._kb_get_metadata, name="kb_get_metadata", mutates=False, advanced=True)
        self._register(toolset, self._kb_get_paths, name="kb_get_paths", mutates=False, advanced=True)
        self._register(toolset, self._kb_validate_storage, name="kb_validate_storage", mutates=False, advanced=True)
        self._register(
            toolset,
            self._kb_relationships_outgoing,
            name="kb_relationships_outgoing",
            mutates=False,
            advanced=True,
        )
        self._register(
            toolset,
            self._kb_relationships_incoming,
            name="kb_relationships_incoming",
            mutates=False,
            advanced=True,
        )
        return toolset

    def _build_kb_advanced_write_toolset(self) -> FunctionToolset[Any]:
        toolset = self._new_function_toolset(layer="knowledgebase", suffix="kb-advanced-write")
        self._register(toolset, self._kb_init, name="kb_init", mutates=True, advanced=True)
        self._register(
            toolset,
            self._kb_replace_metadata_raw,
            name="kb_replace_metadata_raw",
            mutates=True,
            advanced=True,
        )
        return toolset

    def _build_informal_toolset(self) -> FunctionToolset[Any]:
        toolset = self._new_function_toolset(layer="informal", suffix="informal")
        self._register(toolset, self._informal_status, name="informal_status", mutates=False, advanced=False)
        self._register(toolset, self._informal_list_decls, name="informal_list_decls", mutates=False, advanced=False)
        self._register(toolset, self._informal_get_decl, name="informal_get_decl", mutates=False, advanced=False)
        self._register(toolset, self._informal_list_refs, name="informal_list_refs", mutates=False, advanced=False)
        self._register(toolset, self._informal_get_ref, name="informal_get_ref", mutates=False, advanced=False)
        self._register(
            toolset,
            self._informal_decl_dependencies,
            name="informal_decl_dependencies",
            mutates=False,
            advanced=False,
        )
        self._register(
            toolset,
            self._informal_ref_dependencies,
            name="informal_ref_dependencies",
            mutates=False,
            advanced=False,
        )
        self._register(toolset, self._informal_present, name="informal_present", mutates=False, advanced=False)
        return toolset

    def _new_function_toolset(self, *, layer: str, suffix: str) -> FunctionToolset[Any]:
        return FunctionToolset(
            docstring_format="google",
            require_parameter_descriptions=True,
            sequential=True,
            metadata={"source": "aftk", "layer": layer},
            id=self._toolset_id(suffix),
        )

    def _register(
        self,
        toolset: FunctionToolset[Any],
        func: Callable[..., Any],
        *,
        name: str,
        mutates: bool,
        advanced: bool,
    ) -> None:
        toolset.add_function(
            func,
            name=name,
            metadata={"mutates": mutates, "advanced": advanced},
        )

    def _toolset_id(self, suffix: str) -> str | None:
        if self._id is None:
            return None
        return f"{self._id}:{suffix}"

    @staticmethod
    def _normalize_result(result: Any) -> Any:
        if isinstance(result, BaseModel):
            return result.model_dump(mode="python")
        return result

    async def _ensure_open(self, path: str) -> None:
        await self._client.open(path)

    async def _load_single_node_id(self, path: str, line: int, col: int) -> str:
        await self._ensure_open(path)
        loaded = await self._client.load_node(path, line, col)
        if len(loaded.ids) == 1:
            return loaded.ids[0]
        if not loaded.ids:
            raise AftkToolkitExecutionError(
                kind="no_node_at_position",
                message=f"No tactic-state node was found at {path}:{line}:{col}.",
                retryable=True,
                suggested_action="choose_different_position",
                details={"path": path, "line": line, "col": col, "id_count": 0},
            )
        raise AftkToolkitExecutionError(
            kind="ambiguous_node",
            message=f"Multiple tactic-state nodes were found at {path}:{line}:{col}.",
            retryable=True,
            suggested_action="choose_more_specific_position",
            details={
                "path": path,
                "line": line,
                "col": col,
                "id_count": len(loaded.ids),
                "ids": loaded.ids,
            },
        )

    async def _lean_get_hover(self, params: LeanLocationInput) -> HoverResult | None:
        """Get hover information at a Lean source location.

        The file is opened automatically before the query runs.

        Args:
            params: Input parameters describing the Lean file location to inspect.
        """

        await self._ensure_open(params.path)
        return await self._client.get_hover(params.path, params.line, params.col)

    async def _lean_get_plain_goal(self, params: LeanLocationInput) -> PlainGoalResult | None:
        """Get the plain proof goal rendered at a Lean source location.

        The file is opened automatically before the query runs.

        Args:
            params: Input parameters describing the Lean file location to inspect.
        """

        await self._ensure_open(params.path)
        return await self._client.get_plain_goal(params.path, params.line, params.col)

    async def _lean_get_plain_term_goal(self, params: LeanLocationInput) -> PlainTermGoalResult | None:
        """Get the plain term goal rendered at a Lean source location.

        The file is opened automatically before the query runs.

        Args:
            params: Input parameters describing the Lean file location to inspect.
        """

        await self._ensure_open(params.path)
        return await self._client.get_plain_term_goal(params.path, params.line, params.col)

    async def _lean_get_infoview(self, params: LeanLocationInput) -> InfoViewResult:
        """Get the combined infoview payload at a Lean source location.

        The file is opened automatically before the query runs.

        Args:
            params: Input parameters describing the Lean file location to inspect.
        """

        await self._ensure_open(params.path)
        return await self._client.get_infoview(params.path, params.line, params.col)

    async def _lean_get_goals_at(self, params: LeanLocationInput) -> GetGoalsResult:
        """Load the tactic state at a Lean position and return its goals.

        This hides the temporary node-id workflow from the agent.

        Args:
            params: Input parameters describing the Lean file location to inspect.
        """

        node_id = await self._load_single_node_id(params.path, params.line, params.col)
        return await self._client.get_goals(params.path, node_id)

    async def _lean_run_tactic_at(self, params: LeanTacticAtInput) -> RunTacticResult:
        """Run a single tactic at a Lean source location.

        This loads the tactic-state node automatically. If the returned error kind is
        `tactic_failed`, try a different tactic or a nearby position.

        Args:
            params: Input parameters describing the Lean file location and tactic to execute.
        """

        node_id = await self._load_single_node_id(params.path, params.line, params.col)
        return await self._client.run_tactic(params.path, node_id, params.tactic)

    async def _lean_run_tactic_steps_at(self, params: LeanTacticStepsAtInput) -> RunTacticStepsResult:
        """Run several tactics in order at a Lean source location.

        This loads the tactic-state node automatically before executing the tactic sequence.

        Args:
            params: Input parameters describing the Lean file location and tactics to execute.
        """

        node_id = await self._load_single_node_id(params.path, params.line, params.col)
        return await self._client.run_tactic_steps(params.path, node_id, params.tactics)

    async def _lean_open_file(self, params: LeanPathInput) -> OpenResult:
        """Explicitly open a Lean file for advanced workflows.

        This tool is intended for advanced agents that want direct control over file-worker state.

        Args:
            params: Input parameters describing the Lean file to open.
        """

        return await self._client.open(params.path)

    async def _lean_close_file(self, params: LeanPathInput) -> CloseResult:
        """Explicitly close a Lean file for advanced workflows.

        This tool is intended for advanced agents that want direct control over file-worker state.

        Args:
            params: Input parameters describing the Lean file to close.
        """

        return await self._client.close(params.path)

    async def _lean_load_node(self, params: LeanLocationInput) -> LoadNodeResult:
        """Load Lean tactic-state node ids at a source position.

        This advanced tool exposes the raw node-id workflow directly.

        Args:
            params: Input parameters describing the Lean file location to inspect.
        """

        return await self._client.load_node(params.path, params.line, params.col)

    async def _lean_get_goals(self, params: LeanNodeInput) -> GetGoalsResult:
        """Get Lean goals using an existing tactic-state node id.

        This advanced tool expects the file to already be open and the node id to still be valid.

        Args:
            params: Input parameters describing the Lean file path and node id.
        """

        return await self._client.get_goals(params.path, params.node_id)

    async def _lean_run_tactic(self, params: LeanNodeTacticInput) -> RunTacticResult:
        """Run a tactic using an existing Lean tactic-state node id.

        This advanced tool expects the file to already be open and the node id to still be valid.

        Args:
            params: Input parameters describing the Lean file path, node id, and tactic.
        """

        return await self._client.run_tactic(params.path, params.node_id, params.tactic)

    async def _lean_run_tactic_steps(self, params: LeanNodeTacticStepsInput) -> RunTacticStepsResult:
        """Run several tactics using an existing Lean tactic-state node id.

        This advanced tool expects the file to already be open and the node id to still be valid.

        Args:
            params: Input parameters describing the Lean file path, node id, and tactics.
        """

        return await self._client.run_tactic_steps(params.path, params.node_id, params.tactics)

    async def _kb_init(self, params: KnowledgeBaseRootInput) -> KnowledgeBaseStoragePaths:
        """Initialize a knowledge-base root directory.

        This advanced tool mutates on-disk state and is disabled in read-only mode.

        Args:
            params: Input parameters describing the optional knowledge-base root.
        """

        return await self._client.knowledgebase_init(root=params.root)

    async def _kb_status(self, params: KnowledgeBaseRootInput) -> KnowledgeBaseStatusResult:
        """Get high-level status information for a knowledge base.

        Args:
            params: Input parameters describing the optional knowledge-base root.
        """

        return await self._client.knowledgebase_status(root=params.root)

    async def _kb_list_nodes(self, params: KnowledgeBaseListNodesInput) -> KnowledgeBaseListResult:
        """List knowledge-base nodes, optionally filtered by prefix, kind, status, or tag.

        Args:
            params: Input parameters describing the optional knowledge-base root and filters.
        """

        return await self._client.knowledgebase_list(
            root=params.root,
            prefix=params.prefix,
            kind=params.kind,
            status=params.status,
            tag=params.tag,
        )

    async def _kb_show_node(self, params: KnowledgeBaseNodeInput) -> StoredNode:
        """Fetch the full stored node record for a knowledge-base node id.

        Args:
            params: Input parameters describing the knowledge-base node to inspect.
        """

        return await self._client.knowledgebase_show(params.node_id, root=params.root)

    async def _kb_get_body(self, params: KnowledgeBaseNodeInput) -> KnowledgeBaseBodyResult:
        """Fetch only the Markdown body for a knowledge-base node.

        Args:
            params: Input parameters describing the knowledge-base node to inspect.
        """

        return await self._client.knowledgebase_get_body(params.node_id, root=params.root)

    async def _kb_get_metadata(self, params: KnowledgeBaseNodeInput) -> NodeMetadata:
        """Fetch raw metadata for a knowledge-base node.

        This advanced tool exposes the full metadata object directly.

        Args:
            params: Input parameters describing the knowledge-base node to inspect.
        """

        return await self._client.knowledgebase_get_metadata(params.node_id, root=params.root)

    async def _kb_get_paths(self, params: KnowledgeBaseNodeInput) -> KnowledgeBasePathsResult:
        """Fetch storage paths for a knowledge-base node.

        This advanced tool is useful for debugging storage layout.

        Args:
            params: Input parameters describing the knowledge-base node to inspect.
        """

        return await self._client.knowledgebase_get_paths(params.node_id, root=params.root)

    async def _kb_create_node(self, params: KnowledgeBaseCreateNodeInput) -> StoredNode:
        """Create a new knowledge-base node.

        Args:
            params: Input parameters describing the new node to create.
        """

        return await self._client.knowledgebase_create(
            params.node_id,
            title=params.title,
            root=params.root,
            body=params.body,
            kind=params.kind,
            status=params.status,
            summary=params.summary,
            tags=params.tags,
            authors=params.authors,
        )

    async def _kb_rename_node(self, params: KnowledgeBaseRenameNodeInput) -> KnowledgeBaseRenameResult:
        """Rename an existing knowledge-base node id.

        Args:
            params: Input parameters describing the old and new node identifiers.
        """

        return await self._client.knowledgebase_rename(params.old_id, params.new_id, root=params.root)

    async def _kb_delete_node(self, params: KnowledgeBaseNodeInput) -> KnowledgeBaseDeleteResult:
        """Delete a knowledge-base node.

        Args:
            params: Input parameters describing the knowledge-base node to delete.
        """

        return await self._client.knowledgebase_delete(params.node_id, root=params.root)

    async def _kb_set_body(self, params: KnowledgeBaseSetBodyInput) -> StoredNode:
        """Replace the Markdown body of a knowledge-base node.

        Args:
            params: Input parameters describing the node and new Markdown body.
        """

        return await self._client.knowledgebase_set_body(params.node_id, params.body, root=params.root)

    async def _kb_patch_metadata(self, params: KnowledgeBasePatchMetadataInput) -> StoredNode:
        """Patch selected metadata fields for a knowledge-base node.

        This tool reads the current metadata, applies the provided field replacements, and then
        writes the full metadata object back for the agent.

        Args:
            params: Input parameters describing the node and metadata fields to replace.
        """

        metadata = await self._client.knowledgebase_get_metadata(params.node_id, root=params.root)
        replacement = metadata.model_copy(
            update={
                key: value
                for key, value in {
                    "title": params.title,
                    "kind": params.kind,
                    "status": params.status,
                    "summary": params.summary,
                    "tags": params.tags,
                    "authors": params.authors,
                }.items()
                if value is not None
            }
        )
        return await self._client.knowledgebase_replace_metadata(params.node_id, replacement, root=params.root)

    async def _kb_replace_metadata_raw(self, params: KnowledgeBaseReplaceMetadataRawInput) -> StoredNode:
        """Replace a node's metadata using a raw full metadata payload.

        This advanced tool expects a complete metadata object and is easier to misuse than
        `kb_patch_metadata`.

        Args:
            params: Input parameters describing the node and raw metadata payload to store.
        """

        return await self._client.knowledgebase_replace_metadata(
            params.node_id,
            params.metadata,
            root=params.root,
        )

    async def _kb_validate_node(self, params: KnowledgeBaseNodeInput) -> ValidationReport:
        """Validate one knowledge-base node.

        Args:
            params: Input parameters describing the knowledge-base node to validate.
        """

        return await self._client.knowledgebase_validate_node(params.node_id, root=params.root)

    async def _kb_validate_storage(self, params: KnowledgeBaseRootInput) -> ValidationReport:
        """Validate knowledge-base storage structures without validating every node.

        This advanced tool is mainly useful for debugging storage problems.

        Args:
            params: Input parameters describing the optional knowledge-base root.
        """

        return await self._client.knowledgebase_validate_storage(root=params.root)

    async def _kb_validate_all(self, params: KnowledgeBaseRootInput) -> ValidationReport:
        """Validate the entire knowledge base.

        Args:
            params: Input parameters describing the optional knowledge-base root.
        """

        return await self._client.knowledgebase_validate_all(root=params.root)

    async def _kb_search_text(self, params: KnowledgeBaseSearchTextInput) -> SearchResult:
        """Search knowledge-base content using a text query.

        Args:
            params: Input parameters describing the optional root, query text, and result limit.
        """

        return await self._client.knowledgebase_search_text(
            params.query,
            root=params.root,
            limit=params.limit,
        )

    async def _kb_search_tag(self, params: KnowledgeBaseSearchTagInput) -> SearchResult:
        """Search knowledge-base nodes by tag.

        Args:
            params: Input parameters describing the optional root, tag value, and result limit.
        """

        return await self._client.knowledgebase_search_tag(
            params.tag,
            root=params.root,
            limit=params.limit,
        )

    async def _kb_relationships_outgoing(
        self,
        params: KnowledgeBaseNodeInput,
    ) -> KnowledgeBaseOutgoingRelationshipsResult:
        """List outgoing relationships from a knowledge-base node.

        This advanced tool exposes one side of the relationship graph directly.

        Args:
            params: Input parameters describing the knowledge-base node to inspect.
        """

        return await self._client.knowledgebase_relationships_outgoing(params.node_id, root=params.root)

    async def _kb_relationships_incoming(
        self,
        params: KnowledgeBaseNodeInput,
    ) -> KnowledgeBaseIncomingRelationshipsResult:
        """List incoming relationships for a knowledge-base node.

        This advanced tool exposes one side of the relationship graph directly.

        Args:
            params: Input parameters describing the knowledge-base node to inspect.
        """

        return await self._client.knowledgebase_relationships_incoming(params.node_id, root=params.root)

    async def _kb_related(self, params: KnowledgeBaseNodeInput) -> RelatedRelationships:
        """Return both incoming and outgoing relationships for a knowledge-base node.

        Args:
            params: Input parameters describing the knowledge-base node to inspect.
        """

        return await self._client.knowledgebase_relationships_related(params.node_id, root=params.root)

    async def _informal_status(self, params: InformalModulesInput) -> InformalStatusResult:
        """Get high-level tracking status for the informal layer.

        Args:
            params: Input parameters describing the modules to inspect.
        """

        return await self._client.informal_status(params.modules)

    async def _informal_list_decls(self, params: InformalListDeclsInput) -> InformalDeclsResult:
        """List tracked declarations from the informal layer.

        Args:
            params: Input parameters describing the modules and optional filters.
        """

        return await self._client.informal_decls(params.modules, prefix=params.prefix, ref=params.ref)

    async def _informal_get_decl(self, params: InformalGetDeclInput) -> InformalDeclResult:
        """Fetch one tracked declaration from the informal layer.

        Args:
            params: Input parameters describing the modules and declaration name.
        """

        return await self._client.informal_decl(params.modules, params.decl_name)

    async def _informal_list_refs(self, params: InformalListRefsInput) -> InformalRefsResult:
        """List tracked references from the informal layer.

        Args:
            params: Input parameters describing the modules and optional reference prefix.
        """

        return await self._client.informal_refs(params.modules, prefix=params.prefix)

    async def _informal_get_ref(self, params: InformalGetRefInput) -> InformalRefResult:
        """Fetch one tracked reference from the informal layer.

        Args:
            params: Input parameters describing the modules and reference identifier.
        """

        return await self._client.informal_ref(params.modules, params.ref)

    async def _informal_decl_dependencies(self, params: InformalDependenciesInput) -> InformalDeclDepsResult:
        """Return declaration dependencies from the informal layer.

        Args:
            params: Input parameters describing the modules and dependency-query mode.
        """

        return await self._client.informal_decl_deps(params.modules, only_leaves=params.only_leaves)

    async def _informal_ref_dependencies(self, params: InformalDependenciesInput) -> InformalRefDepsResult:
        """Return reference dependencies from the informal layer.

        Args:
            params: Input parameters describing the modules and dependency-query mode.
        """

        return await self._client.informal_ref_deps(params.modules, only_leaves=params.only_leaves)

    async def _informal_present(self, params: InformalPresentInput) -> InformalPresentResult:
        """Render an informal presentation for a knowledge-base reference.

        Args:
            params: Input parameters describing the reference, optional root, and presentation modes.
        """

        return await self._client.informal_present(
            params.ref,
            root=params.root,
            mode=params.mode,
            body_mode=params.body_mode,
        )
