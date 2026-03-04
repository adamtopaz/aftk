#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

git config core.hooksPath .githooks

chmod +x \
  .githooks/pre-commit \
  .githooks/pre-merge-commit \
  .githooks/pre-applypatch \
  .githooks/pre-push \
  scripts/setup-git-hooks.sh

echo "Configured core.hooksPath=.githooks"
echo "Installed sensitive-file hooks: pre-commit, pre-merge-commit, pre-applypatch, pre-push"
echo "Denylist: .githooks/sensitive-paths.txt"
