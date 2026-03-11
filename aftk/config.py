from __future__ import annotations

import os
from pathlib import Path
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field

from aftk_client.client import validate_project_root


PathLike = str | os.PathLike[str]
RelativeFrameworkPath = Annotated[str, Field(min_length=1)]
ProviderModelName = Annotated[str, Field(pattern=r"^[A-Za-z0-9_.-]+:.+$")]


class FrameworkConfigError(ValueError):
    """Raised when framework paths or shared configuration are invalid."""


class FrameworkModel(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)


class AgentModelSettings(FrameworkModel):
    """Per-role model names using Pydantic AI's ``<provider>:<model>`` format."""

    initializer: ProviderModelName | None = None
    orchestrator: ProviderModelName | None = None
    worker: ProviderModelName | None = None


class FrameworkPaths(FrameworkModel):
    project_root: Path
    entrypoint_path: Path
    sources_dir: Path
    state_dir: Path
    project_state_dir: Path
    tasks_dir: Path
    runs_dir: Path

    @classmethod
    def from_project_root(
        cls,
        project_root: PathLike,
        *,
        entrypoint_path: PathLike = "entrypoint.md",
        sources_dir: PathLike = "sources",
        state_dir: PathLike = ".aftk",
    ) -> FrameworkPaths:
        root = validate_project_root(project_root)
        resolved_entrypoint = _resolve_within_root(root, entrypoint_path, label="entrypoint_path")
        if not resolved_entrypoint.exists() or not resolved_entrypoint.is_file():
            raise FrameworkConfigError(
                f"entrypoint_path does not exist or is not a file: {resolved_entrypoint}"
            )

        resolved_sources = _resolve_within_root(root, sources_dir, label="sources_dir")
        if resolved_sources == root:
            raise FrameworkConfigError("sources_dir must be a subdirectory inside project_root")
        if resolved_sources.exists() and not resolved_sources.is_dir():
            raise FrameworkConfigError(f"sources_dir exists but is not a directory: {resolved_sources}")

        resolved_state = _resolve_within_root(root, state_dir, label="state_dir")
        if resolved_state == root:
            raise FrameworkConfigError("state_dir must be a subdirectory inside project_root")

        return cls(
            project_root=root,
            entrypoint_path=resolved_entrypoint,
            sources_dir=resolved_sources,
            state_dir=resolved_state,
            project_state_dir=(resolved_state / "project").resolve(strict=False),
            tasks_dir=(resolved_state / "tasks").resolve(strict=False),
            runs_dir=(resolved_state / "runs").resolve(strict=False),
        )

    def relative_to_project_root(self, path: PathLike) -> RelativeFrameworkPath:
        candidate = Path(path).expanduser().resolve(strict=False)
        try:
            return candidate.relative_to(self.project_root).as_posix()
        except ValueError as exc:
            raise FrameworkConfigError(
                f"path {candidate} is not inside project_root {self.project_root}"
            ) from exc


class FrameworkConfig(FrameworkModel):
    paths: FrameworkPaths
    models: AgentModelSettings = Field(default_factory=AgentModelSettings)

    @classmethod
    def from_project_root(
        cls,
        project_root: PathLike,
        *,
        entrypoint_path: PathLike = "entrypoint.md",
        sources_dir: PathLike = "sources",
        state_dir: PathLike = ".aftk",
        models: AgentModelSettings | None = None,
    ) -> FrameworkConfig:
        return cls(
            paths=FrameworkPaths.from_project_root(
                project_root,
                entrypoint_path=entrypoint_path,
                sources_dir=sources_dir,
                state_dir=state_dir,
            ),
            models=AgentModelSettings() if models is None else models,
        )

    @property
    def project_root(self) -> Path:
        return self.paths.project_root


def _resolve_within_root(project_root: Path, path: PathLike, *, label: str) -> Path:
    candidate = Path(path).expanduser()
    if not candidate.is_absolute():
        candidate = project_root / candidate
    resolved = candidate.resolve(strict=False)
    try:
        resolved.relative_to(project_root)
    except ValueError as exc:
        raise FrameworkConfigError(
            f"{label} must stay within project_root {project_root}: {resolved}"
        ) from exc
    return resolved


__all__ = [
    "AgentModelSettings",
    "FrameworkConfig",
    "FrameworkConfigError",
    "FrameworkModel",
    "FrameworkPaths",
    "PathLike",
    "ProviderModelName",
    "RelativeFrameworkPath",
]
