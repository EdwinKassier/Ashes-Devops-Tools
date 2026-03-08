#!/usr/bin/env bash
set -euo pipefail

mode="${1:-generate}"

cd "$(dirname "$0")/.."

while IFS= read -r module_dir; do
  case "$mode" in
    generate)
      terraform-docs markdown table --config .terraform-docs.yml "$module_dir"
      ;;
    check)
      terraform-docs markdown table --config .terraform-docs.yml --output-check "$module_dir"
      ;;
    *)
      echo "Usage: $0 [generate|check]" >&2
      exit 1
      ;;
  esac
done < <(./scripts/terraform-roots.sh modules)
