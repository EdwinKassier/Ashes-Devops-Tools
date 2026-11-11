#!/usr/bin/env bash
# Pre-commit entry point: regenerate the README of each module that has a changed
# .tf file, exactly as `make docs` does (scripts/module-docs.sh). It runs from the
# repo root, so resource positions in the README match `make docs` output.
set -euo pipefail

[ "$#" -eq 0 ] && exit 0

cd "$(dirname "$0")/.."

modules="$(./scripts/terraform-roots.sh modules)"
while IFS= read -r dir; do
  if printf '%s\n' "$modules" | grep -qxF "$dir"; then
    terraform-docs --config .terraform-docs.yml "$dir"
  fi
done < <(printf '%s\n' "$@" | sed 's#/[^/]*$##' | sort -u)
