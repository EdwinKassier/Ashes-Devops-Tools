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
  all)
    {
      collect_modules
      collect_envs
    } | sort -u
    ;;
  all-json)
    mapfile -t roots < <(
      {
        collect_modules
        collect_envs
      } | sort -u
    )
    emit_json "${roots[@]}"
    ;;
  *)
    echo "Usage: $0 [modules|envs|all|all-json]" >&2
    exit 1
    ;;
esac
