# AGENTS.md

This repository is built for agent-driven autoformalization workflows.

## Mandatory documentation policy

Whenever the project changes, documentation must be updated in the same change set.
This includes (at minimum):

- new features,
- behavior changes,
- CLI changes,
- tool/API surface changes,
- workflow or recommended-usage changes,
- error-model changes.

A feature/behavior change is not considered complete until relevant docs are updated.

## Why this is strict

Project documentation is a core part of how AI agents learn to use these tools effectively.
Keeping docs current is essential for reliable, efficient agent behavior.

## Documentation targets to review on every change

- `README.md`
- `docs/informalize/README.md`
- `docs/informalize/IdReference.md`
- `docs/aftk/README.md`
- `docs/agent-playbook.md`
- `docs/future/autoformalization-tools.md` (when roadmap context changes)
