#!/usr/bin/env bash
set -euo pipefail

mode="${1:-all}"

cd "$(dirname "$0")/.."

collect_modules() {
  # maxdepth 4 covers current structure (modules/<category>/<name>/main.tf = depth 3)
  # and future depth-4 modules (modules/<category>/<name>/<submodule>/main.tf).
  # Without depth 4, any new nested module would be silently excluded from CI validate,
  # lint, and docs generation.
  find modules -mindepth 1 -maxdepth 4 -type f -name main.tf \
    ! -path '*/.terraform/*' ! -path '*/examples/*' | sed 's#/main.tf##' | sort -u
}

collect_envs() {
  # Only include env directories that are Terraform roots (contain at least one .tf file).
  # Directories that hold only .tfvars examples (e.g. envs/workloads/) are excluded.
  find envs -mindepth 1 -maxdepth 1 -type d ! -name '.terraform' | while read -r dir; do
    if find "$dir" -maxdepth 1 -name '*.tf' | grep -q .; then
      echo "$dir"
    fi
  done | sort
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
  for root in ${roots[@]+"${roots[@]}"}; do
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
    roots=()
    while IFS= read -r line; do roots+=("$line"); done < <(
      {
        collect_modules
        collect_envs
        collect_examples
      } | sort -u
    )
    emit_json ${roots[@]+"${roots[@]}"}
    ;;
  *)
    echo "Usage: $0 [modules|envs|examples|all|all-json]" >&2
    exit 1
    ;;
esac
