from __future__ import annotations

import os
from pathlib import Path
from typing import Any, Mapping, Sequence, TypeVar

from pydantic import TypeAdapter, ValidationError

from aftk_client.errors import (
    ConfigurationError,
    InvalidProjectRootError,
    ProjectRootNotFoundError,
    ResponseDecodeContext,
    ResponseDecodeError,
    TransportClosedError,
    jsonrpc_error_from_response,
)
from aftk_client.jsonrpc import JsonRpcErrorResponse
from aftk_client.models import (
    CloseParams,
    CloseResult,
    FileLocationParams,
    FileNodeParams,
    GetGoalsResult,
    HoverResult,
    InfoViewResult,
    InformalDeclDepsResult,
    InformalDeclParams,
    InformalDeclResult,
    InformalDeclsParams,
    InformalDeclsResult,
    InformalDepsParams,
    InformalPresentParams,
    InformalPresentResult,
    InformalRefDepsResult,
    InformalRefParams,
    InformalRefResult,
    InformalRefsParams,
    InformalRefsResult,
    InformalStatusResult,
    InformalModulesParams,
    KnowledgeBaseBodyResult,
    KnowledgeBaseCreateParams,
    KnowledgeBaseDeleteResult,
    KnowledgeBaseListParams,
    KnowledgeBaseListResult,
    KnowledgeBaseNodeParams,
    KnowledgeBaseOutgoingRelationshipsResult,
    KnowledgeBaseIncomingRelationshipsResult,
    KnowledgeBasePathsResult,
    KnowledgeBaseRenameParams,
    KnowledgeBaseRenameResult,
    KnowledgeBaseReplaceMetadataParams,
    KnowledgeBaseRootParams,
    KnowledgeBaseSearchTagParams,
    KnowledgeBaseSearchTextParams,
    KnowledgeBaseSetBodyParams,
    KnowledgeBaseStatusResult,
    KnowledgeBaseStoragePaths,
    LoadNodeResult,
    NodeMetadata,
    OpenParams,
    OpenResult,
    PlainGoalResult,
    PlainTermGoalResult,
    RelatedRelationships,
    RequestModel,
    RunTacticParams,
    RunTacticResult,
    RunTacticStepsParams,
    RunTacticStepsResult,
    SearchResult,
    ShutdownParams,
    ShutdownResult,
    StoredNode,
    ValidationReport,
)
from aftk_client.transport import AsyncJsonRpcSubprocessTransport


DEFAULT_SERVER_COMMAND = ("lake", "exe", "aftk_server")
_LAKEFILE_MARKERS = ("lakefile.lean", "lakefile.toml")

PathLike = str | os.PathLike[str]
ResultT = TypeVar("ResultT")


def is_lake_project_root(path: PathLike) -> bool:
    candidate = Path(path).expanduser()
    if not candidate.exists() or not candidate.is_dir():
        return False
    return any((candidate / marker).is_file() for marker in _LAKEFILE_MARKERS)


def validate_project_root(path: PathLike) -> Path:
    candidate = Path(path).expanduser().resolve(strict=False)
    if not candidate.exists() or not candidate.is_dir():
        raise InvalidProjectRootError(f"project_root does not exist or is not a directory: {candidate}")
    if not is_lake_project_root(candidate):
        raise InvalidProjectRootError(
            f"project_root {candidate} does not contain lakefile.lean or lakefile.toml"
        )
    return candidate


def detect_project_root(path: PathLike) -> Path:
    candidate = Path(path).expanduser().resolve(strict=False)
    start = candidate if candidate.is_dir() else candidate.parent
    for current in (start, *start.parents):
        if is_lake_project_root(current):
            return current.resolve(strict=False)
    raise ProjectRootNotFoundError(
        f"could not find a Lake project root above {candidate}; "
        "looked for lakefile.lean or lakefile.toml"
    )


class AsyncAftkClient:
    def __init__(
        self,
        *,
        command: Sequence[str] = DEFAULT_SERVER_COMMAND,
        project_root: PathLike | None = None,
        cwd: PathLike | None = None,
        env: dict[str, str] | None = None,
        default_timeout: float | None = None,
        shutdown_timeout: float = 5.0,
        exit_timeout: float = 5.0,
        terminate_timeout: float = 2.0,
    ) -> None:
        if not command:
            raise ConfigurationError("command must be a non-empty sequence")

        if project_root is not None and cwd is not None:
            explicit_root = Path(project_root).expanduser().resolve(strict=False)
            cwd_root = Path(cwd).expanduser().resolve(strict=False)
            if explicit_root != cwd_root:
                raise ConfigurationError("project_root and cwd must match when both are provided")

        self._command = tuple(command)
        self._env = dict(env or {})
        self._default_timeout = default_timeout
        self._shutdown_timeout = shutdown_timeout
        self._exit_timeout = exit_timeout
        self._terminate_timeout = terminate_timeout

        explicit_root = project_root if project_root is not None else cwd
        self._configured_project_root = (
            validate_project_root(explicit_root) if explicit_root is not None else None
        )
        self._project_root: Path | None = self._configured_project_root
        self._transport: AsyncJsonRpcSubprocessTransport | None = None

    @classmethod
    def for_file(cls, file_path: PathLike, **kwargs: Any) -> AsyncAftkClient:
        return cls(project_root=detect_project_root(file_path), **kwargs)

    @property
    def project_root(self) -> Path | None:
        return self._project_root

    @property
    def is_started(self) -> bool:
        return self._transport is not None and self._transport.is_started

    async def __aenter__(self) -> AsyncAftkClient:
        await self.start()
        return self

    async def __aexit__(self, exc_type: object, exc: object, tb: object) -> None:
        await self.aclose()

    async def start(self, *, for_file: PathLike | None = None) -> AsyncAftkClient:
        project_root = self._resolve_runtime_project_root(for_file=for_file)
        if self._transport is None:
            self._transport = AsyncJsonRpcSubprocessTransport(
                command=self._command,
                cwd=project_root,
                env=self._env,
                shutdown_timeout=self._shutdown_timeout,
                exit_timeout=self._exit_timeout,
                terminate_timeout=self._terminate_timeout,
            )
        await self._transport.start()
        return self

    async def aclose(self) -> None:
        if self._transport is None:
            return
        transport = self._transport
        self._transport = None
        await transport.aclose()

    async def request(
        self,
        method: str,
        params: RequestModel,
        result_type: type[ResultT] | Any,
        *,
        timeout: float | None = None,
        file_path: PathLike | None = None,
    ) -> ResultT:
        await self.start(for_file=file_path)
        transport = self._require_transport()

        request_id, response = await transport.request(
            method,
            params.model_dump(by_alias=True, exclude_none=True),
            timeout=self._effective_timeout(timeout),
        )

        if isinstance(response, JsonRpcErrorResponse):
            if response.id is None:
                raise TransportClosedError(f"{method} returned an uncorrelatable JSON-RPC error response")
            raise jsonrpc_error_from_response(
                code=response.error.code,
                message=response.error.message,
                data=response.error.data,
                method=method,
                request_id=request_id,
            )

        try:
            adapter = TypeAdapter(result_type)
            return adapter.validate_python(response.result)
        except ValidationError as exc:
            raise ResponseDecodeError(
                f"failed to decode result for {method!r}: {exc}",
                context=ResponseDecodeContext(
                    method=method,
                    request_id=request_id,
                    result_type=self._describe_result_type(result_type),
                ),
                raw_result=response.result,
            ) from exc

    async def open(self, path: PathLike, *, timeout: float | None = None) -> OpenResult:
        wire_path = self._wire_path(path)
        return await self.request(
            "open",
            OpenParams(path=wire_path),
            OpenResult,
            timeout=timeout,
            file_path=wire_path,
        )

    async def close(self, path: PathLike, *, timeout: float | None = None) -> CloseResult:
        wire_path = self._wire_path(path)
        return await self.request(
            "close",
            CloseParams(path=wire_path),
            CloseResult,
            timeout=timeout,
            file_path=wire_path,
        )

    async def load_node(
        self, path: PathLike, line: int, col: int, *, timeout: float | None = None
    ) -> LoadNodeResult:
        wire_path = self._wire_path(path)
        return await self.request(
            "load_node",
            FileLocationParams(path=wire_path, line=line, col=col),
            LoadNodeResult,
            timeout=timeout,
            file_path=wire_path,
        )

    async def get_hover(
        self, path: PathLike, line: int, col: int, *, timeout: float | None = None
    ) -> HoverResult | None:
        wire_path = self._wire_path(path)
        return await self.request(
            "get_hover",
            FileLocationParams(path=wire_path, line=line, col=col),
            HoverResult | None,
            timeout=timeout,
            file_path=wire_path,
        )

    async def get_plain_goal(
        self, path: PathLike, line: int, col: int, *, timeout: float | None = None
    ) -> PlainGoalResult | None:
        wire_path = self._wire_path(path)
        return await self.request(
            "get_plain_goal",
            FileLocationParams(path=wire_path, line=line, col=col),
            PlainGoalResult | None,
            timeout=timeout,
            file_path=wire_path,
        )

    async def get_plain_term_goal(
        self, path: PathLike, line: int, col: int, *, timeout: float | None = None
    ) -> PlainTermGoalResult | None:
        wire_path = self._wire_path(path)
        return await self.request(
            "get_plain_term_goal",
            FileLocationParams(path=wire_path, line=line, col=col),
            PlainTermGoalResult | None,
            timeout=timeout,
            file_path=wire_path,
        )

    async def get_infoview(
        self, path: PathLike, line: int, col: int, *, timeout: float | None = None
    ) -> InfoViewResult:
        wire_path = self._wire_path(path)
        return await self.request(
            "get_infoview",
            FileLocationParams(path=wire_path, line=line, col=col),
            InfoViewResult,
            timeout=timeout,
            file_path=wire_path,
        )

    async def get_goals(
        self, path: PathLike, node_id: str, *, timeout: float | None = None
    ) -> GetGoalsResult:
        wire_path = self._wire_path(path)
        return await self.request(
            "get_goals",
            FileNodeParams(path=wire_path, node_id=node_id),
            GetGoalsResult,
            timeout=timeout,
            file_path=wire_path,
        )

    async def run_tactic(
        self, path: PathLike, node_id: str, tactic: str, *, timeout: float | None = None
    ) -> RunTacticResult:
        wire_path = self._wire_path(path)
        return await self.request(
            "run_tactic",
            RunTacticParams(path=wire_path, node_id=node_id, tactic=tactic),
            RunTacticResult,
            timeout=timeout,
            file_path=wire_path,
        )

    async def run_tactic_steps(
        self,
        path: PathLike,
        node_id: str,
        tactics: Sequence[str],
        *,
        timeout: float | None = None,
    ) -> RunTacticStepsResult:
        wire_path = self._wire_path(path)
        return await self.request(
            "run_tactic_steps",
            RunTacticStepsParams(path=wire_path, node_id=node_id, tactics=list(tactics)),
            RunTacticStepsResult,
            timeout=timeout,
            file_path=wire_path,
        )

    async def knowledgebase_init(
        self, *, root: PathLike | None = None, timeout: float | None = None
    ) -> KnowledgeBaseStoragePaths:
        return await self.request(
            "knowledgebase_init",
            KnowledgeBaseRootParams(root=self._wire_optional_path(root)),
            KnowledgeBaseStoragePaths,
            timeout=timeout,
        )

    async def knowledgebase_status(
        self, *, root: PathLike | None = None, timeout: float | None = None
    ) -> KnowledgeBaseStatusResult:
        return await self.request(
            "knowledgebase_status",
            KnowledgeBaseRootParams(root=self._wire_optional_path(root)),
            KnowledgeBaseStatusResult,
            timeout=timeout,
        )

    async def knowledgebase_list(
        self,
        *,
        root: PathLike | None = None,
        prefix: str | None = None,
        kind: str | None = None,
        status: str | None = None,
        tag: str | None = None,
        timeout: float | None = None,
    ) -> KnowledgeBaseListResult:
        return await self.request(
            "knowledgebase_list",
            KnowledgeBaseListParams(
                root=self._wire_optional_path(root),
                prefix=prefix,
                kind=kind,
                status=status,
                tag=tag,
            ),
            KnowledgeBaseListResult,
            timeout=timeout,
        )

    async def knowledgebase_show(
        self, node_id: str, *, root: PathLike | None = None, timeout: float | None = None
    ) -> StoredNode:
        return await self.request(
            "knowledgebase_show",
            KnowledgeBaseNodeParams(root=self._wire_optional_path(root), id=node_id),
            StoredNode,
            timeout=timeout,
        )

    async def knowledgebase_get_body(
        self, node_id: str, *, root: PathLike | None = None, timeout: float | None = None
    ) -> KnowledgeBaseBodyResult:
        return await self.request(
            "knowledgebase_get_body",
            KnowledgeBaseNodeParams(root=self._wire_optional_path(root), id=node_id),
            KnowledgeBaseBodyResult,
            timeout=timeout,
        )

    async def knowledgebase_get_metadata(
        self, node_id: str, *, root: PathLike | None = None, timeout: float | None = None
    ) -> NodeMetadata:
        return await self.request(
            "knowledgebase_get_metadata",
            KnowledgeBaseNodeParams(root=self._wire_optional_path(root), id=node_id),
            NodeMetadata,
            timeout=timeout,
        )

    async def knowledgebase_get_paths(
        self, node_id: str, *, root: PathLike | None = None, timeout: float | None = None
    ) -> KnowledgeBasePathsResult:
        return await self.request(
            "knowledgebase_get_paths",
            KnowledgeBaseNodeParams(root=self._wire_optional_path(root), id=node_id),
            KnowledgeBasePathsResult,
            timeout=timeout,
        )

    async def knowledgebase_create(
        self,
        node_id: str,
        *,
        title: str,
        root: PathLike | None = None,
        body: str | None = None,
        kind: str | None = None,
        status: str | None = None,
        summary: str | None = None,
        tags: Sequence[str] | None = None,
        authors: Sequence[str] | None = None,
        timeout: float | None = None,
    ) -> StoredNode:
        return await self.request(
            "knowledgebase_create",
            KnowledgeBaseCreateParams(
                root=self._wire_optional_path(root),
                id=node_id,
                title=title,
                body=body,
                kind=kind,
                status=status,
                summary=summary,
                tags=list(tags) if tags is not None else None,
                authors=list(authors) if authors is not None else None,
            ),
            StoredNode,
            timeout=timeout,
        )

    async def knowledgebase_rename(
        self,
        old_id: str,
        new_id: str,
        *,
        root: PathLike | None = None,
        timeout: float | None = None,
    ) -> KnowledgeBaseRenameResult:
        return await self.request(
            "knowledgebase_rename",
            KnowledgeBaseRenameParams(root=self._wire_optional_path(root), old_id=old_id, new_id=new_id),
            KnowledgeBaseRenameResult,
            timeout=timeout,
        )

    async def knowledgebase_delete(
        self, node_id: str, *, root: PathLike | None = None, timeout: float | None = None
    ) -> KnowledgeBaseDeleteResult:
        return await self.request(
            "knowledgebase_delete",
            KnowledgeBaseNodeParams(root=self._wire_optional_path(root), id=node_id),
            KnowledgeBaseDeleteResult,
            timeout=timeout,
        )

    async def knowledgebase_set_body(
        self,
        node_id: str,
        body: str,
        *,
        root: PathLike | None = None,
        timeout: float | None = None,
    ) -> StoredNode:
        return await self.request(
            "knowledgebase_set_body",
            KnowledgeBaseSetBodyParams(root=self._wire_optional_path(root), id=node_id, body=body),
            StoredNode,
            timeout=timeout,
        )

    async def knowledgebase_replace_metadata(
        self,
        node_id: str,
        metadata: Mapping[str, Any] | NodeMetadata,
        *,
        root: PathLike | None = None,
        timeout: float | None = None,
    ) -> StoredNode:
        return await self.request(
            "knowledgebase_replace_metadata",
            KnowledgeBaseReplaceMetadataParams(
                root=self._wire_optional_path(root),
                id=node_id,
                metadata=self._metadata_payload(metadata),
            ),
            StoredNode,
            timeout=timeout,
        )

    async def knowledgebase_validate_metadata(
        self, node_id: str, *, root: PathLike | None = None, timeout: float | None = None
    ) -> ValidationReport:
        return await self.request(
            "knowledgebase_validate_metadata",
            KnowledgeBaseNodeParams(root=self._wire_optional_path(root), id=node_id),
            ValidationReport,
            timeout=timeout,
        )

    async def knowledgebase_validate_storage(
        self, *, root: PathLike | None = None, timeout: float | None = None
    ) -> ValidationReport:
        return await self.request(
            "knowledgebase_validate_storage",
            KnowledgeBaseRootParams(root=self._wire_optional_path(root)),
            ValidationReport,
            timeout=timeout,
        )

    async def knowledgebase_validate_node(
        self, node_id: str, *, root: PathLike | None = None, timeout: float | None = None
    ) -> ValidationReport:
        return await self.request(
            "knowledgebase_validate_node",
            KnowledgeBaseNodeParams(root=self._wire_optional_path(root), id=node_id),
            ValidationReport,
            timeout=timeout,
        )

    async def knowledgebase_validate_all(
        self, *, root: PathLike | None = None, timeout: float | None = None
    ) -> ValidationReport:
        return await self.request(
            "knowledgebase_validate_all",
            KnowledgeBaseRootParams(root=self._wire_optional_path(root)),
            ValidationReport,
            timeout=timeout,
        )

    async def knowledgebase_search_text(
        self,
        query: str,
        *,
        root: PathLike | None = None,
        limit: int | None = None,
        timeout: float | None = None,
    ) -> SearchResult:
        return await self.request(
            "knowledgebase_search_text",
            KnowledgeBaseSearchTextParams(root=self._wire_optional_path(root), query=query, limit=limit),
            SearchResult,
            timeout=timeout,
        )

    async def knowledgebase_search_tag(
        self,
        tag: str,
        *,
        root: PathLike | None = None,
        limit: int | None = None,
        timeout: float | None = None,
    ) -> SearchResult:
        return await self.request(
            "knowledgebase_search_tag",
            KnowledgeBaseSearchTagParams(root=self._wire_optional_path(root), tag=tag, limit=limit),
            SearchResult,
            timeout=timeout,
        )

    async def knowledgebase_relationships_outgoing(
        self, node_id: str, *, root: PathLike | None = None, timeout: float | None = None
    ) -> KnowledgeBaseOutgoingRelationshipsResult:
        return await self.request(
            "knowledgebase_relationships_outgoing",
            KnowledgeBaseNodeParams(root=self._wire_optional_path(root), id=node_id),
            KnowledgeBaseOutgoingRelationshipsResult,
            timeout=timeout,
        )

    async def knowledgebase_relationships_incoming(
        self, node_id: str, *, root: PathLike | None = None, timeout: float | None = None
    ) -> KnowledgeBaseIncomingRelationshipsResult:
        return await self.request(
            "knowledgebase_relationships_incoming",
            KnowledgeBaseNodeParams(root=self._wire_optional_path(root), id=node_id),
            KnowledgeBaseIncomingRelationshipsResult,
            timeout=timeout,
        )

    async def knowledgebase_relationships_related(
        self, node_id: str, *, root: PathLike | None = None, timeout: float | None = None
    ) -> RelatedRelationships:
        return await self.request(
            "knowledgebase_relationships_related",
            KnowledgeBaseNodeParams(root=self._wire_optional_path(root), id=node_id),
            RelatedRelationships,
            timeout=timeout,
        )

    async def informal_status(
        self, modules: Sequence[str], *, timeout: float | None = None
    ) -> InformalStatusResult:
        return await self.request(
            "informal_status",
            InformalModulesParams(modules=list(modules)),
            InformalStatusResult,
            timeout=timeout,
        )

    async def informal_decls(
        self,
        modules: Sequence[str],
        *,
        prefix: str | None = None,
        ref: str | None = None,
        timeout: float | None = None,
    ) -> InformalDeclsResult:
        return await self.request(
            "informal_decls",
            InformalDeclsParams(modules=list(modules), prefix=prefix, ref=ref),
            InformalDeclsResult,
            timeout=timeout,
        )

    async def informal_decl(
        self, modules: Sequence[str], decl_name: str, *, timeout: float | None = None
    ) -> InformalDeclResult:
        return await self.request(
            "informal_decl",
            InformalDeclParams(modules=list(modules), decl_name=decl_name),
            InformalDeclResult,
            timeout=timeout,
        )

    async def informal_refs(
        self,
        modules: Sequence[str],
        *,
        prefix: str | None = None,
        timeout: float | None = None,
    ) -> InformalRefsResult:
        return await self.request(
            "informal_refs",
            InformalRefsParams(modules=list(modules), prefix=prefix),
            InformalRefsResult,
            timeout=timeout,
        )

    async def informal_ref(
        self, modules: Sequence[str], ref: str, *, timeout: float | None = None
    ) -> InformalRefResult:
        return await self.request(
            "informal_ref",
            InformalRefParams(modules=list(modules), ref=ref),
            InformalRefResult,
            timeout=timeout,
        )

    async def informal_decl_deps(
        self,
        modules: Sequence[str],
        *,
        only_leaves: bool = False,
        timeout: float | None = None,
    ) -> InformalDeclDepsResult:
        return await self.request(
            "informal_decl_deps",
            InformalDepsParams(modules=list(modules), only_leaves=only_leaves),
            InformalDeclDepsResult,
            timeout=timeout,
        )

    async def informal_ref_deps(
        self,
        modules: Sequence[str],
        *,
        only_leaves: bool = False,
        timeout: float | None = None,
    ) -> InformalRefDepsResult:
        return await self.request(
            "informal_ref_deps",
            InformalDepsParams(modules=list(modules), only_leaves=only_leaves),
            InformalRefDepsResult,
            timeout=timeout,
        )

    async def informal_present(
        self,
        ref: str,
        *,
        root: PathLike | None = None,
        mode: str | None = None,
        body_mode: str | None = None,
        timeout: float | None = None,
    ) -> InformalPresentResult:
        return await self.request(
            "informal_present",
            InformalPresentParams(
                root=self._wire_optional_path(root),
                ref=ref,
                mode=mode,
                body_mode=body_mode,
            ),
            InformalPresentResult,
            timeout=timeout,
        )

    async def shutdown(self, *, timeout: float | None = None) -> ShutdownResult:
        return await self.request(
            "shutdown",
            ShutdownParams(),
            ShutdownResult,
            timeout=timeout,
        )

    def _wire_path(self, path: PathLike) -> str:
        candidate = Path(path).expanduser()
        if candidate.is_absolute():
            return str(candidate.resolve(strict=False))

        base = self._project_root or self._configured_project_root
        if base is not None:
            return str((base / candidate).resolve(strict=False))

        return str(candidate.resolve(strict=False))

    def _wire_optional_path(self, path: PathLike | None) -> str | None:
        if path is None:
            return None
        return self._wire_path(path)

    def _metadata_payload(self, metadata: Mapping[str, Any] | NodeMetadata) -> dict[str, Any]:
        if isinstance(metadata, NodeMetadata):
            return metadata.model_dump(by_alias=True, exclude_none=True)
        return dict(metadata)

    def _resolve_runtime_project_root(self, *, for_file: PathLike | None = None) -> Path:
        if self._project_root is not None:
            return self._project_root

        if for_file is not None:
            self._project_root = detect_project_root(for_file)
            return self._project_root

        self._project_root = Path.cwd().resolve(strict=False)
        return self._project_root

    def _effective_timeout(self, timeout: float | None) -> float | None:
        return self._default_timeout if timeout is None else timeout

    def _require_transport(self) -> AsyncJsonRpcSubprocessTransport:
        if self._transport is None:
            raise TransportClosedError("client transport is not initialized")
        return self._transport

    def _describe_result_type(self, result_type: type[ResultT] | Any) -> str:
        return getattr(result_type, "__name__", repr(result_type))
