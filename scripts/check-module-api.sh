#!/usr/bin/env bash
# Module API guard. A change that removes or renames a module input (variable)
# or output, or deletes a module, is a breaking change for every consumer that
# pins this repository. It must carry a breaking-change commit in the range:
# a `type!:` / `type(scope)!:` subject or a `BREAKING CHANGE:` footer. That
# commit in turn needs an UPGRADING.md entry (meta-lint and `make commit-check`
# enforce it). Adding inputs or outputs is not breaking.
# Policy: docs/policies/versioning-and-compatibility.md.
#
#   scripts/check-module-api.sh <base-ref>
#
# Compares merge-base(<base-ref>, HEAD) with HEAD for every module directory
# under modules/ whose top-level *.tf files changed. Declarations are collected
# per directory, so moving a variable or output between files of one module is
# not a removal. A module's examples/ and tests/ directories are not module API.
# CI: meta-lint on pull requests (base = origin/<base branch>).
# Locally: make module-api (COMMIT_BASE, default origin/main).
set -euo pipefail

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
  echo "usage: $0 <base-ref>   (for example origin/main)" >&2
  exit 2
fi
git rev-parse --verify --quiet "$1^{commit}" >/dev/null \
  || { echo "check-module-api: base ref '$1' not found (fetch it, or set COMMIT_BASE)" >&2; exit 2; }
base="$(git merge-base "$1" HEAD)" \
  || { echo "check-module-api: no merge-base with '$1' (fetch full history)" >&2; exit 2; }

# names <rev> <dir> <variable|output>: sorted declared names in the top-level
# .tf files of <dir> at <rev> (empty when the directory does not exist there).
names() {
  local rev="$1" dir="$2" kind="$3" f
  git ls-tree --name-only "${rev}" -- "${dir}/" 2>/dev/null | while IFS= read -r f; do
    case "${f}" in *.tf) git show "${rev}:${f}" ;; esac
  done | sed -nE "s/^${kind}[[:space:]]+\"?([A-Za-z0-9_-]+)\"?[[:space:]]*\\{.*/\\1/p" | sort -u
}

removed=()
while IFS= read -r dir; do
  [ -n "${dir}" ] || continue
  for kind in variable output; do
    while IFS= read -r n; do
      [ -n "${n}" ] && removed+=("${dir}: removed ${kind} ${n}")
    done < <(comm -23 <(names "${base}" "${dir}" "${kind}") <(names HEAD "${dir}" "${kind}"))
  done
done < <(git diff --name-only "${base}" HEAD -- 'modules/' \
  | grep -E '\.tf$' | grep -Ev '/(examples|tests)/' | xargs -r -n1 dirname | sort -u)

if [ "${#removed[@]}" -eq 0 ]; then
  echo "check-module-api: no module input or output removed"
  exit 0
fi
if git log --format=%B "${base}..HEAD" | grep -Eq '^[a-z]+(\([^)]*\))?!:|^BREAKING[ -]CHANGE'; then
  printf 'check-module-api: breaking change declared for:\n'
  printf '  %s\n' "${removed[@]}"
  exit 0
fi
{
  printf '::error::Module API removed without a breaking-change commit (type!: or a BREAKING CHANGE: footer, plus an UPGRADING.md entry). Prefer deprecating first: docs/policies/versioning-and-compatibility.md\n'
  printf '  %s\n' "${removed[@]}"
} >&2
exit 1
