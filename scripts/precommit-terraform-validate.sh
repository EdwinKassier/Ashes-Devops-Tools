#!/usr/bin/env bash
# Pre-commit entry point: validate each directory that holds a staged .tf file,
# but only the directories `make validate-all` validates. Both read the
# directory list from scripts/terraform-roots.sh (all), and both skip
# `terraform validate` for a module that declares configuration_aliases: such a
# module cannot be validated as a standalone root (CLAUDE.md, AWS modules #2).
# The composing roots, examples/ and mock tests cover it instead.
#
# Examples are skipped here too. git exports GIT_DIR to hooks, and terraform
# init on a git-sourced example then runs its git checkout against this
# repository and moves HEAD. `make validate-all` and CI validate examples.
# The GIT_* variables are also unset before each terraform call.
set -euo pipefail

[ "$#" -eq 0 ] && exit 0

cd "$(dirname "$0")/.."

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

roots="$(./scripts/terraform-roots.sh all)"
rc=0
while IFS= read -r dir; do
  [ -n "$dir" ] || continue
  case "/$dir/" in */examples/*) continue ;; esac
  grep -qxF "$dir" <<<"$roots" || continue
  if grep -rqE 'configuration_aliases[[:space:]]*=' "$dir" --include='*.tf'; then
    echo "Skipping validate for $dir (declares configuration_aliases; covered by examples/, composing roots and mock tests)"
    continue
  fi
  init_ok=0
  for attempt in 1 2; do
    if terraform -chdir="$dir" init -backend=false -input=false >/dev/null; then
      init_ok=1
      break
    fi
    [ "$attempt" -eq 2 ] || rm -rf "$dir/.terraform"
  done
  if [ "$init_ok" -ne 1 ]; then
    echo "terraform init failed: $dir" >&2
    rc=1
    continue
  fi
  if ! terraform -chdir="$dir" validate -no-color; then
    echo "terraform validate failed: $dir" >&2
    rc=1
  fi
done < <(printf '%s\n' "$@" | sed 's#/[^/]*$##' | sort -u)

exit "$rc"
