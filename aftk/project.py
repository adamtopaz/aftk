from __future__ import annotations

import hashlib
import os
from datetime import datetime, timezone
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import Annotated

from pydantic import AwareDatetime, Field

from aftk.config import FrameworkConfig, FrameworkConfigError, FrameworkModel, FrameworkPaths


PathLike = str | os.PathLike[str]
RelativeProjectPath = Annotated[str, Field(min_length=1)]
Sha256Hex = Annotated[str, Field(pattern=r"^[0-9a-f]{64}$")]


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


class ProjectSnapshotError(RuntimeError):
    """Raised when the framework cannot scan or persist project snapshot state."""


class SourceFileRecord(FrameworkModel):
    path: RelativeProjectPath
    size_bytes: int = Field(ge=0)
    sha256: Sha256Hex


class LeanFileRecord(FrameworkModel):
    path: RelativeProjectPath
    size_bytes: int = Field(ge=0)
    sha256: Sha256Hex


class ProjectSnapshot(FrameworkModel):
    schema_version: int = Field(default=1, ge=1)
    project_root: str
    generated_state_dir: RelativeProjectPath
    entrypoint_path: RelativeProjectPath
    entrypoint_text: str
    entrypoint_sha256: Sha256Hex
    sources_dir: RelativeProjectPath
    sources_present: bool
    source_inventory: list[SourceFileRecord] = Field(default_factory=list)
    lakefile_path: RelativeProjectPath
    lean_files: list[LeanFileRecord] = Field(default_factory=list)
    created_at: AwareDatetime = Field(default_factory=utc_now)


class ProjectSnapshotStore:
    SNAPSHOT_FILE_NAME = "snapshot.json"

    def __init__(self, root: PathLike | FrameworkPaths) -> None:
        store_root = root.project_state_dir if isinstance(root, FrameworkPaths) else Path(root)
        self.root = Path(store_root).expanduser().resolve(strict=False)
        self.snapshot_path = self.root / self.SNAPSHOT_FILE_NAME

    def ensure_layout(self) -> None:
        self.root.mkdir(parents=True, exist_ok=True)

    def has_snapshot(self) -> bool:
        return self.snapshot_path.is_file()

    def save_snapshot(self, snapshot: ProjectSnapshot) -> Path:
        self.ensure_layout()
        _write_model_json(self.snapshot_path, snapshot, indent=2)
        return self.snapshot_path

    def load_snapshot(self) -> ProjectSnapshot:
        return ProjectSnapshot.model_validate_json(self.snapshot_path.read_text(encoding="utf-8"))


class ProjectSnapshotService:
    EXCLUDED_LEAN_DIRECTORIES = frozenset({".aftk", ".git", ".lake", "sources"})

    def __init__(self, config: FrameworkConfig | FrameworkPaths) -> None:
        self.config = config if isinstance(config, FrameworkConfig) else FrameworkConfig(paths=config)
        self.paths = self.config.paths
        self.store = ProjectSnapshotStore(self.paths)

    def build_snapshot(self, *, now: datetime | None = None) -> ProjectSnapshot:
        try:
            lakefile_path = self._discover_lakefile()
            entrypoint_text = self.paths.entrypoint_path.read_text(encoding="utf-8")
        except (FrameworkConfigError, OSError) as exc:
            raise ProjectSnapshotError(str(exc)) from exc

        if self.paths.sources_dir.exists() and not self.paths.sources_dir.is_dir():
            raise ProjectSnapshotError(f"sources_dir exists but is not a directory: {self.paths.sources_dir}")

        timestamp = utc_now() if now is None else now
        source_inventory = [self._source_record(path) for path in self._iter_files(self.paths.sources_dir)]
        lean_files = [
            self._lean_record(path)
            for path in self._iter_files(
                self.paths.project_root,
                excluded_dir_names=self.EXCLUDED_LEAN_DIRECTORIES,
            )
            if path.suffix == ".lean" and path.name != "lakefile.lean"
        ]

        return ProjectSnapshot(
            project_root=str(self.paths.project_root),
            generated_state_dir=self.paths.relative_to_project_root(self.paths.state_dir),
            entrypoint_path=self.paths.relative_to_project_root(self.paths.entrypoint_path),
            entrypoint_text=entrypoint_text,
            entrypoint_sha256=_sha256_file(self.paths.entrypoint_path),
            sources_dir=self.paths.relative_to_project_root(self.paths.sources_dir),
            sources_present=self.paths.sources_dir.is_dir(),
            source_inventory=source_inventory,
            lakefile_path=self.paths.relative_to_project_root(lakefile_path),
            lean_files=lean_files,
            created_at=timestamp,
        )

    def build_and_save_snapshot(self, *, now: datetime | None = None) -> ProjectSnapshot:
        snapshot = self.build_snapshot(now=now)
        self.store.save_snapshot(snapshot)
        return snapshot

    def load_snapshot(self) -> ProjectSnapshot:
        return self.store.load_snapshot()

    def _discover_lakefile(self) -> Path:
        for marker in _LAKEFILE_MARKERS:
            candidate = (self.paths.project_root / marker).resolve(strict=False)
            if candidate.is_file():
                return candidate
        raise ProjectSnapshotError(
            f"project_root {self.paths.project_root} does not contain lakefile.lean or lakefile.toml"
        )

    def _source_record(self, path: Path) -> SourceFileRecord:
        return SourceFileRecord(
            path=self.paths.relative_to_project_root(path),
            size_bytes=path.stat().st_size,
            sha256=_sha256_file(path),
        )

    def _lean_record(self, path: Path) -> LeanFileRecord:
        return LeanFileRecord(
            path=self.paths.relative_to_project_root(path),
            size_bytes=path.stat().st_size,
            sha256=_sha256_file(path),
        )

    def _iter_files(self, root: Path, *, excluded_dir_names: frozenset[str] = frozenset()) -> list[Path]:
        if not root.exists():
            return []
        if not root.is_dir():
            raise ProjectSnapshotError(f"scan root is not a directory: {root}")

        files: list[Path] = []
        for current_root, dirnames, filenames in os.walk(root, topdown=True, followlinks=False):
            dirnames[:] = sorted(name for name in dirnames if name not in excluded_dir_names)
            for filename in sorted(filenames):
                files.append((Path(current_root) / filename).resolve(strict=False))
        return files


_LAKEFILE_MARKERS = ("lakefile.lean", "lakefile.toml")


def _write_model_json(path: Path, model: FrameworkModel, *, indent: int | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = model.model_dump_json(indent=indent)
    with NamedTemporaryFile(
        "w",
        encoding="utf-8",
        dir=path.parent,
        prefix=f"{path.name}.",
        suffix=".tmp",
        delete=False,
    ) as handle:
        handle.write(payload)
        handle.write("\n")
        temp_path = Path(handle.name)
    temp_path.replace(path)


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(65536)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


__all__ = [
    "LeanFileRecord",
    "PathLike",
    "ProjectSnapshot",
    "ProjectSnapshotError",
    "ProjectSnapshotService",
    "ProjectSnapshotStore",
    "RelativeProjectPath",
    "Sha256Hex",
    "SourceFileRecord",
    "utc_now",
]
