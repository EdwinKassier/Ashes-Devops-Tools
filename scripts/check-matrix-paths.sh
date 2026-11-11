#!/usr/bin/env bash
# Fail when the control matrix cites a repo path that does not exist, or when a
# control ID appears twice (CMP-17).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

files=()
for f in docs/compliance/control-matrix.md docs/compliance/framework-crosswalk.md; do
  [ -f "$f" ] && files+=("$f")
done

fail=0
while IFS= read -r p; do
  case "$p" in
    modules/* | envs/* | policies/* | scripts/* | .github/* | docs/* | config/* | examples/* | templates/*)
      if [ ! -e "$p" ]; then
        echo "control-matrix cites a missing path: $p"
        fail=1
      fi
      ;;
  esac
done < <(grep -ohE '`[A-Za-z0-9_./-]+/[A-Za-z0-9_./-]+`' "${files[@]}" | tr -d '`' | sort -u)

dups="$(grep -oE '^\| [A-Z]+-[0-9]+ ' docs/compliance/control-matrix.md | sort | uniq -d || true)"
if [ -n "$dups" ]; then
  echo "duplicate control IDs: $dups"
  fail=1
fi
exit "$fail"
