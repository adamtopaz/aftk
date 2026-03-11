from __future__ import annotations

import argparse
from collections.abc import Sequence

from aftk.config import FrameworkConfig
from aftk.inspection import FrameworkInspectionService


DEFAULT_MAX_RUNS = 20
DEFAULT_MAX_ATTEMPTS = 20
DEFAULT_MAX_EVENTS = 20
DEFAULT_MAX_TASK_LINES = 20
DEFAULT_MAX_ATTEMPT_LINES = 10
DEFAULT_MAX_EVENT_LINES = 10
DEFAULT_MAX_RUN_LINES = 10
DEFAULT_JSON_INDENT = 2


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="aftk-inspect",
        description="Inspect persistent AFTK framework state for a Lake project.",
    )
    parser.add_argument(
        "project_root",
        nargs="?",
        default=".",
        help="Path to the Lake project root to inspect (default: current directory).",
    )
    parser.add_argument(
        "--entrypoint-path",
        default="entrypoint.md",
        help="Project-relative path to the framework entrypoint file (default: entrypoint.md).",
    )
    parser.add_argument(
        "--sources-dir",
        default="sources",
        help="Project-relative path to the optional sources directory (default: sources).",
    )
    parser.add_argument(
        "--state-dir",
        default=".aftk",
        help="Project-relative path to the generated framework state directory (default: .aftk).", 
    )
    parser.add_argument(
        "--json",
        action="store_true",
        dest="json_output",
        help="Emit a JSON inspection report instead of the text report.",
    )
    parser.add_argument(
        "--indent",
        type=int,
        default=DEFAULT_JSON_INDENT,
        help=f"Indent level for JSON output (default: {DEFAULT_JSON_INDENT}).",
    )
    parser.add_argument(
        "--max-runs",
        type=int,
        default=DEFAULT_MAX_RUNS,
        help=f"Maximum number of recent runs to inspect (default: {DEFAULT_MAX_RUNS}).",
    )
    parser.add_argument(
        "--max-attempts",
        type=int,
        default=DEFAULT_MAX_ATTEMPTS,
        help=f"Maximum number of recent attempts to inspect (default: {DEFAULT_MAX_ATTEMPTS}).",
    )
    parser.add_argument(
        "--max-events",
        type=int,
        default=DEFAULT_MAX_EVENTS,
        help=f"Maximum number of recent task events to inspect (default: {DEFAULT_MAX_EVENTS}).",
    )
    parser.add_argument(
        "--max-task-lines",
        type=int,
        default=DEFAULT_MAX_TASK_LINES,
        help=f"Maximum number of task rows to show in text output (default: {DEFAULT_MAX_TASK_LINES}).",
    )
    parser.add_argument(
        "--max-attempt-lines",
        type=int,
        default=DEFAULT_MAX_ATTEMPT_LINES,
        help=f"Maximum number of attempt rows to show in text output (default: {DEFAULT_MAX_ATTEMPT_LINES}).",
    )
    parser.add_argument(
        "--max-event-lines",
        type=int,
        default=DEFAULT_MAX_EVENT_LINES,
        help=f"Maximum number of event rows to show in text output (default: {DEFAULT_MAX_EVENT_LINES}).",
    )
    parser.add_argument(
        "--max-run-lines",
        type=int,
        default=DEFAULT_MAX_RUN_LINES,
        help=f"Maximum number of run rows to show in text output (default: {DEFAULT_MAX_RUN_LINES}).",
    )
    parser.add_argument(
        "--rebuild-rollups",
        action="store_true",
        help="Rebuild project rollups from per-run logs if the aggregate rollup file is missing.",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(list(argv) if argv is not None else None)

    try:
        config = FrameworkConfig.from_project_root(
            args.project_root,
            entrypoint_path=args.entrypoint_path,
            sources_dir=args.sources_dir,
            state_dir=args.state_dir,
        )
        inspector = FrameworkInspectionService(config)
        report = inspector.build_report(
            max_runs=args.max_runs,
            max_attempts=args.max_attempts,
            max_events=args.max_events,
            rebuild_rollups=args.rebuild_rollups,
        )
        if args.json_output:
            output = inspector.render_json_report(report, indent=args.indent)
        else:
            output = inspector.render_text_report(
                report,
                max_task_lines=args.max_task_lines,
                max_attempt_lines=args.max_attempt_lines,
                max_event_lines=args.max_event_lines,
                max_run_lines=args.max_run_lines,
            )
    except Exception as exc:
        parser.exit(1, f"aftk-inspect: {exc}\n")

    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
