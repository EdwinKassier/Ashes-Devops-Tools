#!/usr/bin/env bash
# Pre-commit entry point: regenerate the README of each module or root that has a
# changed .tf file, exactly as `make docs` does (scripts/module-docs.sh). Both read
# the directory list from scripts/docs-targets.sh. It runs from the repo root, so
# resource positions in the README match `make docs` output.
set -euo pipefail

[ "$#" -eq 0 ] && exit 0

cd "$(dirname "$0")/.."

targets="$(./scripts/docs-targets.sh)"
while IFS= read -r dir; do
  line="$(printf '%s\n' "$targets" | awk -F'\t' -v d="$dir" '$2 == d' | head -n 1)"
  [ -n "$line" ] || continue
  terraform-docs --config "${line%%$'\t'*}" "$dir"
done < <(printf '%s\n' "$@" | sed 's#/[^/]*$##' | sort -u)
