#!/usr/bin/env bash
# Generate (or check) the terraform-docs block of every module and every
# deployable root. The directory list comes from scripts/docs-targets.sh.
set -euo pipefail

mode="${1:-generate}"

cd "$(dirname "$0")/.."

case "$mode" in
  generate | check) ;;
  *)
    echo "Usage: $0 [generate|check]" >&2
    exit 1
    ;;
esac

fail=0
while IFS=$'\t' read -r config dir; do
  case "$mode" in
    generate)
      terraform-docs --config "$config" "$dir"
      ;;
    check)
      # Aggregate failures across all directories instead of stopping at the first
      # stale README, so a single run reports every one that needs `make docs`.
      terraform-docs --config "$config" --output-check "$dir" || fail=1
      ;;
  esac
done < <(./scripts/docs-targets.sh)

exit "$fail"
