from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field


class ToolkitModel(BaseModel):
    """Base model for Pydantic AI toolkit inputs and outputs."""

    model_config = ConfigDict(extra="forbid", populate_by_name=True)


class AftkToolErrorInfo(ToolkitModel):
    """Structured error information returned to an agent."""

    kind: str = Field(description="Stable machine-readable error kind.")
    message: str = Field(description="Human-readable explanation of the tool failure.")
    retryable: bool = Field(description="Whether retrying or adjusting the request could succeed.")
    suggested_action: str | None = Field(
        default=None,
        description="Short machine-readable suggestion describing what the agent should try next.",
    )
    details: dict[str, Any] | None = Field(
        default=None,
        description="Optional structured debugging or domain details about the failure.",
    )


class AftkToolSuccess(ToolkitModel):
    """Successful tool-call envelope."""

    ok: Literal[True] = True
    tool: str = Field(description="The tool name that produced this result.")
    data: Any = Field(description="Tool-specific success payload.")


class AftkToolFailure(ToolkitModel):
    """Failed tool-call envelope."""

    ok: Literal[False] = False
    tool: str = Field(description="The tool name that failed.")
    error: AftkToolErrorInfo = Field(description="Structured failure information.")


AftkToolResult = AftkToolSuccess | AftkToolFailure


class LeanLocationInput(ToolkitModel):
    """Input for tools that operate on a Lean source location."""

    path: str = Field(
        description=(
            "Path to a Lean source file. Relative paths are resolved against the client's "
            "configured project root when one is available."
        )
    )
    line: int = Field(ge=1, description="1-based line number in the Lean source file.")
    col: int = Field(ge=1, description="1-based column number in the Lean source file.")


class LeanTacticAtInput(LeanLocationInput):
    """Input for running a single tactic at a Lean source location."""

    tactic: str = Field(description="Single tactic command to execute at the selected position.")


class LeanTacticStepsAtInput(LeanLocationInput):
    """Input for running several tactics at a Lean source location."""

    tactics: list[str] = Field(
        min_length=1,
        description="Non-empty list of tactic commands to execute in order at the selected position.",
    )


class LeanPathInput(ToolkitModel):
    """Input for advanced tools that explicitly open or close Lean files."""

    path: str = Field(
        description=(
            "Path to a Lean source file. Relative paths are resolved against the client's "
            "configured project root when one is available."
        )
    )


class LeanNodeInput(ToolkitModel):
    """Input for advanced tools that operate on a previously loaded Lean node id."""

    path: str = Field(
        description=(
            "Path to a Lean source file. Relative paths are resolved against the client's "
            "configured project root when one is available."
        )
    )
    node_id: str = Field(description="Existing Lean tactic-state node identifier.")


class LeanNodeTacticInput(LeanNodeInput):
    """Input for advanced tools that run a single tactic using a node id."""

    tactic: str = Field(description="Single tactic command to execute using the provided node id.")


class LeanNodeTacticStepsInput(LeanNodeInput):
    """Input for advanced tools that run several tactics using a node id."""

    tactics: list[str] = Field(
        min_length=1,
        description="Non-empty list of tactic commands to execute in order using the provided node id.",
    )


class KnowledgeBaseRootInput(ToolkitModel):
    """Input for knowledge-base tools that optionally accept a root path."""

    root: str | None = Field(
        default=None,
        description=(
            "Optional path to a knowledge-base root directory. Omit this to use the server's "
            "default knowledge-base root."
        ),
    )


class KnowledgeBaseListNodesInput(KnowledgeBaseRootInput):
    """Input for listing knowledge-base nodes with optional filters."""

    prefix: str | None = Field(default=None, description="Optional node-id prefix filter.")
    kind: str | None = Field(default=None, description="Optional node kind filter.")
    status: str | None = Field(default=None, description="Optional node status filter.")
    tag: str | None = Field(default=None, description="Optional tag filter.")


class KnowledgeBaseNodeInput(KnowledgeBaseRootInput):
    """Input for tools that target a single knowledge-base node id."""

    node_id: str = Field(description="Knowledge-base node identifier.")


class KnowledgeBaseSearchTextInput(KnowledgeBaseRootInput):
    """Input for full-text knowledge-base search."""

    query: str = Field(description="Text query to search for in knowledge-base content.")
    limit: int | None = Field(
        default=None,
        ge=1,
        description="Optional maximum number of search hits to return.",
    )


class KnowledgeBaseSearchTagInput(KnowledgeBaseRootInput):
    """Input for tag-based knowledge-base search."""

    tag: str = Field(description="Tag value to search for.")
    limit: int | None = Field(
        default=None,
        ge=1,
        description="Optional maximum number of search hits to return.",
    )


class KnowledgeBaseCreateNodeInput(KnowledgeBaseRootInput):
    """Input for creating a new knowledge-base node."""

    node_id: str = Field(description="Identifier for the new knowledge-base node.")
    title: str = Field(description="Human-readable title for the new node.")
    body: str | None = Field(default=None, description="Optional initial Markdown body.")
    kind: str | None = Field(default=None, description="Optional node kind value.")
    status: str | None = Field(default=None, description="Optional node status value.")
    summary: str | None = Field(default=None, description="Optional one-paragraph summary.")
    tags: list[str] | None = Field(default=None, description="Optional list of tags for the node.")
    authors: list[str] | None = Field(
        default=None,
        description="Optional list of author names for the node.",
    )


class KnowledgeBaseSetBodyInput(KnowledgeBaseRootInput):
    """Input for replacing the Markdown body of an existing knowledge-base node."""

    node_id: str = Field(description="Knowledge-base node identifier.")
    body: str = Field(description="New full Markdown body to store for the node.")


class KnowledgeBasePatchMetadataInput(KnowledgeBaseRootInput):
    """Input for patching selected knowledge-base metadata fields."""

    node_id: str = Field(description="Knowledge-base node identifier.")
    title: str | None = Field(default=None, description="Optional replacement title.")
    kind: str | None = Field(default=None, description="Optional replacement kind value.")
    status: str | None = Field(default=None, description="Optional replacement status value.")
    summary: str | None = Field(default=None, description="Optional replacement summary text.")
    tags: list[str] | None = Field(default=None, description="Optional full replacement tag list.")
    authors: list[str] | None = Field(
        default=None,
        description="Optional full replacement author list.",
    )


class KnowledgeBaseRenameNodeInput(KnowledgeBaseRootInput):
    """Input for renaming a knowledge-base node."""

    old_id: str = Field(description="Current knowledge-base node identifier.")
    new_id: str = Field(description="Replacement knowledge-base node identifier.")


class KnowledgeBaseReplaceMetadataRawInput(KnowledgeBaseRootInput):
    """Input for advanced raw metadata replacement."""

    node_id: str = Field(description="Knowledge-base node identifier.")
    metadata: dict[str, Any] = Field(
        description=(
            "Complete metadata payload to store. This advanced tool expects the full metadata "
            "object, not just a partial patch."
        )
    )


class InformalModulesInput(ToolkitModel):
    """Input for informal tools that query one or more modules."""

    modules: list[str] = Field(
        min_length=1,
        description="Non-empty list of Lean module names to query.",
    )


class InformalListDeclsInput(InformalModulesInput):
    """Input for listing tracked declarations in the informal layer."""

    prefix: str | None = Field(default=None, description="Optional declaration-name prefix filter.")
    ref: str | None = Field(default=None, description="Optional reference filter.")


class InformalGetDeclInput(InformalModulesInput):
    """Input for fetching one tracked declaration from the informal layer."""

    decl_name: str = Field(description="Fully qualified Lean declaration name.")


class InformalListRefsInput(InformalModulesInput):
    """Input for listing tracked references in the informal layer."""

    prefix: str | None = Field(default=None, description="Optional reference prefix filter.")


class InformalGetRefInput(InformalModulesInput):
    """Input for fetching one tracked reference from the informal layer."""

    ref: str = Field(description="Tracked informal reference identifier.")


class InformalDependenciesInput(InformalModulesInput):
    """Input for informal dependency tools."""

    only_leaves: bool = Field(
        default=False,
        description="Whether to return only leaf dependencies instead of the full dependency table.",
    )


class InformalPresentInput(KnowledgeBaseRootInput):
    """Input for rendering an informal presentation of a knowledge-base reference."""

    ref: str = Field(description="Knowledge-base reference or node id to present.")
    mode: str | None = Field(
        default=None,
        description="Optional presentation mode requested from the server.",
    )
    body_mode: str | None = Field(
        default=None,
        description="Optional body rendering mode requested from the server.",
    )
