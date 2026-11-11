#!/usr/bin/env bash
# Print every directory whose README carries a generated terraform-docs block,
# as "<config><TAB><dir>" lines. `make docs` / `make docs-check`
# (scripts/module-docs.sh) and the pre-commit hook
# (scripts/precommit-terraform-docs.sh) both read this list, so they cannot
# drift apart.
set -euo pipefail

cd "$(dirname "$0")/.."

while IFS= read -r dir; do
  printf '.terraform-docs.yml\t%s\n' "$dir"
done < <(./scripts/terraform-roots.sh modules)

while IFS= read -r dir; do
  printf '.terraform-docs-envs.yml\t%s\n' "$dir"
done < <(./scripts/terraform-roots.sh envs)
