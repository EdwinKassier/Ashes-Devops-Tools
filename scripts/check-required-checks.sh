#!/usr/bin/env bash
# Required-status-check guard. docs/guides/BRANCH_PROTECTION.md carries the
# `gh api .../branches/main/protection` command operators paste. Every context in
# its `"contexts":[...]` list must be a context GitHub actually reports, i.e. the
# display `name:` of a NON-matrix job in .github/workflows/. A matrix job emits one
# context per leg ("Terraform Tests (shard 3)"), so its bare name never reports and
# would block every PR forever. Contexts starting with "Terraform Cloud/" are
# external (TFC VCS integration) and are skipped.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

doc=docs/guides/BRANCH_PROTECTION.md
wf_dir=.github/workflows

contexts_line=$(grep -oE '"contexts":\[[^]]*\]' "$doc" || true)
if [ -z "$contexts_line" ]; then
  echo "ERROR: no \"contexts\":[...] list found in $doc" >&2
  exit 1
fi

# A job counts only if it has no `matrix:` and its name has no ${{ }} expression
# (GitHub suffixes matrix legs, so neither form ever reports a bare name). Jobs
# without `name:` report their job id. Reusable-workflow callers (`uses:`) report
# "<caller> / <callee job>", never their own name, so they are excluded as well.
wf_files=()
while IFS= read -r f; do wf_files+=("$f"); done < <(find "$wf_dir" -maxdepth 1 \( -name '*.yml' -o -name '*.yaml' \) | sort)
names=$(awk '
  function flush() { if (job != "" && !matrix && !reusable && name !~ /\$\{\{/) print (name != "" ? name : job) }
  FNR == 1 { flush(); injobs=0; job=""; name=""; matrix=0; reusable=0 }
  /^jobs:/ { injobs=1; next }
  injobs && /^[^ #]/ { flush(); injobs=0; job="" }
  injobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { flush(); job=$1; sub(/:$/, "", job); name=""; matrix=0; reusable=0; next }
  injobs && job != "" && /^    name:/ { name=$0; sub(/^    name:[[:space:]]*/, "", name); gsub(/^["\x27]|["\x27]$/, "", name) }
  injobs && job != "" && /^      matrix:/ { matrix=1 }
  injobs && job != "" && /^    uses:/ { reusable=1 }
  END { flush() }
' "${wf_files[@]}" | sort -u)

fail=0
checked=0
while IFS= read -r ctx; do
  [ -n "$ctx" ] || continue
  checked=$((checked + 1))
  case "$ctx" in "Terraform Cloud/"*) echo "  skip (external): $ctx"; continue ;; esac
  if printf '%s\n' "$names" | grep -Fxq -- "$ctx"; then
    echo "  ok: $ctx"
  else
    echo "ERROR: required context '$ctx' in $doc is not a non-matrix job name in $wf_dir" >&2
    echo "       (a sharded matrix job never reports its bare name — require 'Validation Summary' instead)" >&2
    fail=1
  fi
done < <(printf '%s\n' "$contexts_line" | sed -E 's/^"contexts":\[//; s/\]$//' | tr ',' '\n' | sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//')

[ "$checked" -gt 0 ] || { echo "ERROR: empty contexts list in $doc" >&2; exit 1; }
[ "$fail" -eq 0 ] && echo "Required status checks: all $checked context(s) resolve to reported job names."
exit "$fail"
