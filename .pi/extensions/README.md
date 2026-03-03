# Local pi extension: AFTK hub tools

This directory contains a project-local pi extension:

- `aftk-hub.ts`

## What it adds

Tools:

- `aftk_open`
- `aftk_close`
- `aftk_load_node`
- `aftk_get_hover`
- `aftk_get_plain_goal`
- `aftk_get_plain_term_goal`
- `aftk_get_infoview`
- `aftk_get_goals`
- `aftk_run_tactic`
- `aftk_run_tactic_steps`
- `aftk_shutdown`

Command:

- `/aftk-hub-stop` (stops the managed `aftk_server` process)

## Usage

1. Build the binaries:

```bash
lake build aftk_server aftk_file_worker
```

2. Start pi in this repo (extension is auto-discovered from `.pi/extensions/`), or run `/reload` in an existing pi session.

3. Ask pi to use the `aftk_*` tools for Lean hub interaction.
