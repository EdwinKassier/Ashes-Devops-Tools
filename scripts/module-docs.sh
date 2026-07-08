#!/usr/bin/env bash
set -euo pipefail

mode="${1:-generate}"

cd "$(dirname "$0")/.."

fail=0
while IFS= read -r module_dir; do
  case "$mode" in
    generate)
      terraform-docs --config .terraform-docs.yml "$module_dir"
      ;;
    check)
      # Aggregate failures across all modules instead of stopping at the first
      # stale README, so a single run reports every module that needs `make docs`.
      terraform-docs --config .terraform-docs.yml --output-check "$module_dir" || fail=1
      ;;
    *)
      echo "Usage: $0 [generate|check]" >&2
      exit 1
      ;;
  esac
done < <(./scripts/terraform-roots.sh modules)

exit "$fail"
