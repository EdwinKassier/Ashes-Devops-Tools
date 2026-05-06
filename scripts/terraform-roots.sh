#!/usr/bin/env bash
set -euo pipefail

mode="${1:-all}"

cd "$(dirname "$0")/.."

collect_modules() {
  find modules -mindepth 1 -maxdepth 3 -type f -name main.tf \
    ! -path '*/.terraform/*' | sed 's#/main.tf##' | sort -u
}

collect_envs() {
  find envs -mindepth 1 -maxdepth 1 -type d \
    ! -name '.terraform' | sort
}

# Examples are only included when they have a versions.tf (self-contained).
# Searches both the top-level examples/ directory and examples/ subdirectories
# inside any module (HashiCorp module convention: modules/<name>/examples/<example>/).
collect_examples() {
  {
    find examples -mindepth 1 -maxdepth 2 -type f -name versions.tf \
      ! -path '*/.terraform/*' | sed 's#/versions.tf##'
    find modules -mindepth 3 -maxdepth 5 -type f -name versions.tf \
      -path '*/examples/*' ! -path '*/.terraform/*' | sed 's#/versions.tf##'
  } | sort -u
}

emit_json() {
  local roots=("$@")
  printf '['
  local first=1
  local root
  for root in "${roots[@]}"; do
    if [ $first -eq 0 ]; then
      printf ','
    fi
    first=0
    printf '"%s"' "$root"
  done
  printf ']\n'
}

case "$mode" in
  modules)
    collect_modules
    ;;
  envs)
    collect_envs
    ;;
  examples)
    collect_examples
    ;;
  all)
    {
      collect_modules
      collect_envs
      collect_examples
    } | sort -u
    ;;
  all-json)
    mapfile -t roots < <(
      {
        collect_modules
        collect_envs
        collect_examples
      } | sort -u
    )
    emit_json "${roots[@]}"
    ;;
  *)
    echo "Usage: $0 [modules|envs|examples|all|all-json]" >&2
    exit 1
    ;;
esac
