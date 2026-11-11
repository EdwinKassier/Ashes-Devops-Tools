#!/usr/bin/env bash
# Print every directory whose README carries a generated terraform-docs block,
# as "<config><TAB><dir>" lines. `make docs` / `make docs-check`
# (scripts/module-docs.sh) and the pre-commit hook
# (scripts/precommit-terraform-docs.sh) both read this list, so they cannot
# drift apart. It fails when discovery finds nothing, so a broken helper cannot
# make the docs gate pass with nothing checked.
set -euo pipefail

cd "$(dirname "$0")/.."

modules="$(./scripts/terraform-roots.sh modules)"
envs="$(./scripts/terraform-roots.sh envs)"
if [ -z "$modules" ] || [ -z "$envs" ]; then
  echo "docs-targets.sh: terraform-roots.sh returned no modules or no envs roots" >&2
  exit 1
fi

while IFS= read -r dir; do
  printf '.terraform-docs.yml\t%s\n' "$dir"
done <<<"$modules"

while IFS= read -r dir; do
  printf '.terraform-docs-envs.yml\t%s\n' "$dir"
done <<<"$envs"
