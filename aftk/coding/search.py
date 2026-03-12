from __future__ import annotations

import logging
import os
from fnmatch import fnmatch
from pathlib import Path

from aftk.coding.filesystem import CodingError, PathLike, ProjectSandbox
from aftk.coding.models import CodingActionKind, ProjectPath, SearchMatch


class ProjectSearchService(ProjectSandbox):
    def list_project_files(
        self,
        *,
        include_globs: list[str] | None = None,
        exclude_globs: list[str] | None = None,
        limit: int = 200,
    ) -> list[ProjectPath]:
        if limit < 1:
            raise ValueError("limit must be at least 1")
        results = [ProjectPath(path=self.relative_path(path)) for path in self._iter_project_files(include_globs, exclude_globs, limit)]
        self._record_action(
            CodingActionKind.LIST_PROJECT_FILES,
            details={
                "include_globs": [] if include_globs is None else list(include_globs),
                "exclude_globs": [] if exclude_globs is None else list(exclude_globs),
                "limit": limit,
                "result_count": len(results),
            },
        )
        self._log(
            logging.DEBUG,
            "list_project_files",
            "listed project files",
            tool_name="list_project_files",
            summary=f"{len(results)} results",
        )
        return results

    def search_project_text(
        self,
        query: str,
        *,
        include_globs: list[str] | None = None,
        exclude_globs: list[str] | None = None,
        limit: int = 100,
    ) -> list[SearchMatch]:
        if not query:
            raise ValueError("query must not be empty")
        if limit < 1:
            raise ValueError("limit must be at least 1")

        matches: list[SearchMatch] = []
        for path in self._iter_project_files(include_globs, exclude_globs, limit=None):
            if _is_probably_binary(path):
                continue
            try:
                lines = self._read_text_file(path).splitlines()
            except (CodingError, OSError):
                continue
            for line_index, line in enumerate(lines, start=1):
                column = line.find(query)
                if column == -1:
                    continue
                matches.append(
                    SearchMatch(
                        path=self.relative_path(path),
                        line=line_index,
                        column=column + 1,
                        snippet=line.strip(),
                    )
                )
                if len(matches) >= limit:
                    self._record_action(
                        CodingActionKind.SEARCH_PROJECT_TEXT,
                        details={
                            "query": query,
                            "include_globs": [] if include_globs is None else list(include_globs),
                            "exclude_globs": [] if exclude_globs is None else list(exclude_globs),
                            "limit": limit,
                            "result_count": len(matches),
                        },
                    )
                    self._log(
                        logging.DEBUG,
                        "search_project_text",
                        "searched project text",
                        tool_name="search_project_text",
                        summary=f"query={query!r} results={len(matches)}",
                    )
                    return matches

        self._record_action(
            CodingActionKind.SEARCH_PROJECT_TEXT,
            details={
                "query": query,
                "include_globs": [] if include_globs is None else list(include_globs),
                "exclude_globs": [] if exclude_globs is None else list(exclude_globs),
                "limit": limit,
                "result_count": len(matches),
            },
        )
        self._log(
            logging.DEBUG,
            "search_project_text",
            "searched project text",
            tool_name="search_project_text",
            summary=f"query={query!r} results={len(matches)}",
        )
        return matches

    def _iter_project_files(
        self,
        include_globs: list[str] | None,
        exclude_globs: list[str] | None,
        limit: int | None,
    ) -> list[Path]:
        matched: list[Path] = []
        for current_root, dirnames, filenames in os.walk(self.project_root, topdown=True, followlinks=False):
            dirnames[:] = sorted(name for name in dirnames if name not in self.excluded_search_dir_names)
            for filename in sorted(filenames):
                path = (Path(current_root) / filename).resolve(strict=False)
                relative = self.relative_path(path)
                if include_globs and not any(fnmatch(relative, pattern) for pattern in include_globs):
                    continue
                if exclude_globs and any(fnmatch(relative, pattern) for pattern in exclude_globs):
                    continue
                matched.append(path)
                if limit is not None and len(matched) >= limit:
                    return matched
        return matched


def _is_probably_binary(path: Path) -> bool:
    with path.open("rb") as handle:
        return b"\0" in handle.read(2048)


__all__ = ["ProjectSearchService"]
