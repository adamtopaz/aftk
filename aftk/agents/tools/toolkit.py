from __future__ import annotations

from collections.abc import Callable, Sequence
from typing import Any

from pydantic_ai import FunctionToolset

from aftk.agents.tools.retries import wrap_async_tool_errors
from aftk_client import (
    AsyncAftkClient,
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
    KnowledgeBaseIncomingRelationshipsResult,
    KnowledgeBaseListResult,
    KnowledgeBaseOutgoingRelationshipsResult,
    KnowledgeBasePathsResult,
    KnowledgeBaseStatusResult,
    LoadNodeResult,
    OpenResult,
    PlainGoalResult,
    PlainTermGoalResult,
    RelatedRelationships,
    RunTacticResult,
    RunTacticStepsResult,
    SearchResult,
    StoredNode,
)


DEFAULT_TOOLKIT_TOOL_RETRIES = 2


class ToolkitQueryTools:
    def __init__(self, client: AsyncAftkClient) -> None:
        self.client = client

    async def open(self, path: str, timeout_seconds: float | None = None) -> OpenResult:
        """Open or reuse a Lean file session before using file-scoped Lean query tools."""
        return await self.client.open(path, timeout=timeout_seconds)

    async def close(self, path: str, timeout_seconds: float | None = None) -> CloseResult:
        """Close a Lean file session when you are done with file-scoped Lean queries."""
        return await self.client.close(path, timeout=timeout_seconds)

    async def load_node(self, path: str, line: int, col: int, timeout_seconds: float | None = None) -> LoadNodeResult:
        """Load the Lean syntax node at a 1-indexed file position."""
        return await self.client.load_node(path, line, col, timeout=timeout_seconds)

    async def get_hover(self, path: str, line: int, col: int, timeout_seconds: float | None = None) -> HoverResult | None:
        """Get Lean hover text at a 1-indexed file position."""
        return await self.client.get_hover(path, line, col, timeout=timeout_seconds)

    async def get_plain_goal(
        self,
        path: str,
        line: int,
        col: int,
        timeout_seconds: float | None = None,
    ) -> PlainGoalResult | None:
        """Get the rendered Lean proof goals at a 1-indexed file position."""
        return await self.client.get_plain_goal(path, line, col, timeout=timeout_seconds)

    async def get_plain_term_goal(
        self,
        path: str,
        line: int,
        col: int,
        timeout_seconds: float | None = None,
    ) -> PlainTermGoalResult | None:
        """Get the rendered Lean term goal at a 1-indexed file position."""
        return await self.client.get_plain_term_goal(path, line, col, timeout=timeout_seconds)

    async def get_infoview(
        self,
        path: str,
        line: int,
        col: int,
        timeout_seconds: float | None = None,
    ) -> InfoViewResult:
        """Get the combined Lean infoview payload at a 1-indexed file position."""
        return await self.client.get_infoview(path, line, col, timeout=timeout_seconds)

    async def get_goals(self, path: str, node_id: str, timeout_seconds: float | None = None) -> GetGoalsResult:
        """Get proof goals for a previously loaded Lean node id."""
        return await self.client.get_goals(path, node_id, timeout=timeout_seconds)

    async def run_tactic(
        self,
        path: str,
        node_id: str,
        tactic: str,
        timeout_seconds: float | None = None,
    ) -> RunTacticResult:
        """Run a single tactic against a Lean goal node and return the next goals."""
        return await self.client.run_tactic(path, node_id, tactic, timeout=timeout_seconds)

    async def run_tactic_steps(
        self,
        path: str,
        node_id: str,
        tactics: Sequence[str],
        timeout_seconds: float | None = None,
    ) -> RunTacticStepsResult:
        """Run a sequence of tactics against a Lean goal node."""
        return await self.client.run_tactic_steps(path, node_id, tactics, timeout=timeout_seconds)

    async def knowledgebase_status(
        self,
        root: str | None = None,
        timeout_seconds: float | None = None,
    ) -> KnowledgeBaseStatusResult:
        """Inspect knowledge-base storage status for the project or an explicit root."""
        return await self.client.knowledgebase_status(root=root, timeout=timeout_seconds)

    async def knowledgebase_list(
        self,
        root: str | None = None,
        prefix: str | None = None,
        kind: str | None = None,
        status: str | None = None,
        tag: str | None = None,
        timeout_seconds: float | None = None,
    ) -> KnowledgeBaseListResult:
        """List knowledge-base nodes with optional prefix, kind, status, or tag filters."""
        return await self.client.knowledgebase_list(
            root=root,
            prefix=prefix,
            kind=kind,
            status=status,
            tag=tag,
            timeout=timeout_seconds,
        )

    async def knowledgebase_show(
        self,
        node_id: str,
        root: str | None = None,
        timeout_seconds: float | None = None,
    ) -> StoredNode:
        """Load a full knowledge-base node, including metadata and body."""
        return await self.client.knowledgebase_show(node_id, root=root, timeout=timeout_seconds)

    async def knowledgebase_get_body(
        self,
        node_id: str,
        root: str | None = None,
        timeout_seconds: float | None = None,
    ) -> KnowledgeBaseBodyResult:
        """Get the body text for a knowledge-base node."""
        return await self.client.knowledgebase_get_body(node_id, root=root, timeout=timeout_seconds)

    async def knowledgebase_get_paths(
        self,
        node_id: str,
        root: str | None = None,
        timeout_seconds: float | None = None,
    ) -> KnowledgeBasePathsResult:
        """Get filesystem paths for a stored knowledge-base node."""
        return await self.client.knowledgebase_get_paths(node_id, root=root, timeout=timeout_seconds)

    async def knowledgebase_search_text(
        self,
        query: str,
        root: str | None = None,
        limit: int | None = None,
        timeout_seconds: float | None = None,
    ) -> SearchResult:
        """Search the knowledge base by free text."""
        return await self.client.knowledgebase_search_text(
            query,
            root=root,
            limit=limit,
            timeout=timeout_seconds,
        )

    async def knowledgebase_search_tag(
        self,
        tag: str,
        root: str | None = None,
        limit: int | None = None,
        timeout_seconds: float | None = None,
    ) -> SearchResult:
        """Search the knowledge base for nodes carrying a specific tag."""
        return await self.client.knowledgebase_search_tag(
            tag,
            root=root,
            limit=limit,
            timeout=timeout_seconds,
        )

    async def knowledgebase_relationships_outgoing(
        self,
        node_id: str,
        root: str | None = None,
        timeout_seconds: float | None = None,
    ) -> KnowledgeBaseOutgoingRelationshipsResult:
        """Get outgoing relationships for a knowledge-base node."""
        return await self.client.knowledgebase_relationships_outgoing(
            node_id,
            root=root,
            timeout=timeout_seconds,
        )

    async def knowledgebase_relationships_incoming(
        self,
        node_id: str,
        root: str | None = None,
        timeout_seconds: float | None = None,
    ) -> KnowledgeBaseIncomingRelationshipsResult:
        """Get incoming relationships for a knowledge-base node."""
        return await self.client.knowledgebase_relationships_incoming(
            node_id,
            root=root,
            timeout=timeout_seconds,
        )

    async def knowledgebase_relationships_related(
        self,
        node_id: str,
        root: str | None = None,
        timeout_seconds: float | None = None,
    ) -> RelatedRelationships:
        """Get both incoming and outgoing relationships for a knowledge-base node."""
        return await self.client.knowledgebase_relationships_related(
            node_id,
            root=root,
            timeout=timeout_seconds,
        )

    async def informal_status(
        self,
        modules: Sequence[str],
        timeout_seconds: float | None = None,
    ) -> InformalStatusResult:
        """Inspect informal-layer availability for one or more Lean modules."""
        return await self.client.informal_status(modules, timeout=timeout_seconds)

    async def informal_decls(
        self,
        modules: Sequence[str],
        prefix: str | None = None,
        ref: str | None = None,
        timeout_seconds: float | None = None,
    ) -> InformalDeclsResult:
        """List informal declarations for one or more modules."""
        return await self.client.informal_decls(
            modules,
            prefix=prefix,
            ref=ref,
            timeout=timeout_seconds,
        )

    async def informal_decl(
        self,
        modules: Sequence[str],
        decl_name: str,
        timeout_seconds: float | None = None,
    ) -> InformalDeclResult:
        """Load a single informal declaration by name."""
        return await self.client.informal_decl(modules, decl_name, timeout=timeout_seconds)

    async def informal_refs(
        self,
        modules: Sequence[str],
        prefix: str | None = None,
        timeout_seconds: float | None = None,
    ) -> InformalRefsResult:
        """List informal references for one or more modules."""
        return await self.client.informal_refs(modules, prefix=prefix, timeout=timeout_seconds)

    async def informal_ref(
        self,
        modules: Sequence[str],
        ref: str,
        timeout_seconds: float | None = None,
    ) -> InformalRefResult:
        """Load a single informal reference by id."""
        return await self.client.informal_ref(modules, ref, timeout=timeout_seconds)

    async def informal_decl_deps(
        self,
        modules: Sequence[str],
        only_leaves: bool = False,
        timeout_seconds: float | None = None,
    ) -> InformalDeclDepsResult:
        """Get informal declaration dependencies for one or more modules."""
        return await self.client.informal_decl_deps(
            modules,
            only_leaves=only_leaves,
            timeout=timeout_seconds,
        )

    async def informal_ref_deps(
        self,
        modules: Sequence[str],
        only_leaves: bool = False,
        timeout_seconds: float | None = None,
    ) -> InformalRefDepsResult:
        """Get informal reference dependencies for one or more modules."""
        return await self.client.informal_ref_deps(
            modules,
            only_leaves=only_leaves,
            timeout=timeout_seconds,
        )

    async def informal_present(
        self,
        ref: str,
        root: str | None = None,
        mode: str | None = None,
        body_mode: str | None = None,
        timeout_seconds: float | None = None,
    ) -> InformalPresentResult:
        """Render an informal presentation for a declaration or reference."""
        return await self.client.informal_present(
            ref,
            root=root,
            mode=mode,
            body_mode=body_mode,
            timeout=timeout_seconds,
        )

    def tool_functions(self) -> tuple[Callable[..., object], ...]:
        return (
            wrap_async_tool_errors(self.open),
            wrap_async_tool_errors(self.close),
            wrap_async_tool_errors(self.load_node),
            wrap_async_tool_errors(self.get_hover),
            wrap_async_tool_errors(self.get_plain_goal),
            wrap_async_tool_errors(self.get_plain_term_goal),
            wrap_async_tool_errors(self.get_infoview),
            wrap_async_tool_errors(self.get_goals),
            wrap_async_tool_errors(self.run_tactic),
            wrap_async_tool_errors(self.run_tactic_steps),
            wrap_async_tool_errors(self.knowledgebase_status),
            wrap_async_tool_errors(self.knowledgebase_list),
            wrap_async_tool_errors(self.knowledgebase_show),
            wrap_async_tool_errors(self.knowledgebase_get_body),
            wrap_async_tool_errors(self.knowledgebase_get_paths),
            wrap_async_tool_errors(self.knowledgebase_search_text),
            wrap_async_tool_errors(self.knowledgebase_search_tag),
            wrap_async_tool_errors(self.knowledgebase_relationships_outgoing),
            wrap_async_tool_errors(self.knowledgebase_relationships_incoming),
            wrap_async_tool_errors(self.knowledgebase_relationships_related),
            wrap_async_tool_errors(self.informal_status),
            wrap_async_tool_errors(self.informal_decls),
            wrap_async_tool_errors(self.informal_decl),
            wrap_async_tool_errors(self.informal_refs),
            wrap_async_tool_errors(self.informal_ref),
            wrap_async_tool_errors(self.informal_decl_deps),
            wrap_async_tool_errors(self.informal_ref_deps),
            wrap_async_tool_errors(self.informal_present),
        )


def build_toolkit_query_toolset(toolkit_client: AsyncAftkClient) -> Any:
    tools = ToolkitQueryTools(toolkit_client)
    return FunctionToolset(
        tools=list(tools.tool_functions()),
        max_retries=DEFAULT_TOOLKIT_TOOL_RETRIES,
        sequential=True,
    )


__all__ = [
    "DEFAULT_TOOLKIT_TOOL_RETRIES",
    "ToolkitQueryTools",
    "build_toolkit_query_toolset",
]
