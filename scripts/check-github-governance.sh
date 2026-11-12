#!/usr/bin/env bash
# GitHub Actions governance guards (run by scripts/check-consistency.sh, so by
# `make consistency` and the meta-lint job).
#
# Egress: every job that holds a secret (a `secrets.` reference other than
# secrets.GITHUB_TOKEN) or a GitHub OIDC token (`id-token: write`) must run
# step-security/harden-runner with `egress-policy: block` and an
# allowed-endpoints list traced from its steps. A job that cannot block yet is
# listed in EXCEPTIONS below with the reason. Reusable-workflow caller jobs
# (job-level `uses:`) have no steps here; the called workflow's jobs are checked
# in their own file.
#
#   scripts/check-github-governance.sh [workflow-dir]   (default .github/workflows)
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
dir="${1:-.github/workflows}"

# <workflow file name>:<job id>  <reason>. Keep each reason true on main.
EXCEPTIONS=(
)

is_exception() {
  local key="$1" e
  for e in "${EXCEPTIONS[@]+"${EXCEPTIONS[@]}"}"; do
    [ "${e%% *}" = "$key" ] && return 0
  done
  return 1
}

fail=0
checked=0
shopt -s nullglob
files=("$dir"/*.yml "$dir"/*.yaml)
if [ "${#files[@]}" -eq 0 ]; then
  echo "check-github-governance: no workflow files in ${dir}" >&2
  exit 1
fi

for wf in "${files[@]}"; do
  # One line per job: <job id> <holds-credential 0|1> <blocks 0|1> <reusable 0|1>
  while read -r job holds blocks reusable; do
    [ "$holds" = 1 ] || continue
    checked=$((checked + 1))
    key="$(basename "$wf"):${job}"
    if [ "$reusable" = 1 ]; then
      continue
    fi
    if [ "$blocks" = 1 ]; then
      echo "  ok   ${key} holds a credential and blocks egress"
    elif is_exception "$key"; then
      echo "  ok   ${key} holds a credential; listed exception (audit mode)"
    else
      echo "  FAIL ${key} holds a secret or an OIDC token but harden-runner is not egress-policy: block" >&2
      fail=1
    fi
  done < <(awk '
    function flush() {
      if (job != "") print job, holds, blocks, reusable
      job = ""; holds = 0; blocks = 0; reusable = 0
    }
    /^jobs:[[:space:]]*$/ { injobs = 1; next }
    injobs && /^[^[:space:]#]/ { flush(); injobs = 0 }
    injobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { flush(); job = $1; sub(/:$/, "", job); next }
    injobs && job != "" {
      line = $0
      sub(/[[:space:]]+#.*$/, "", line)
      if (line ~ /^[[:space:]]*#/) next
      if (line ~ /^    uses:/) reusable = 1
      if (line ~ /id-token:[[:space:]]*write/) holds = 1
      tmp = line
      while (match(tmp, /secrets\.[A-Za-z0-9_]+/)) {
        name = substr(tmp, RSTART + 8, RLENGTH - 8)
        if (name != "GITHUB_TOKEN") holds = 1
        tmp = substr(tmp, RSTART + RLENGTH)
      }
      if (line ~ /egress-policy:[[:space:]]*block[[:space:]]*$/) blocks = 1
    }
    END { flush() }
  ' "$wf")
done

# A listed exception must name a workflow file that exists.
for e in "${EXCEPTIONS[@]+"${EXCEPTIONS[@]}"}"; do
  key="${e%% *}"
  wf="${dir}/${key%%:*}"
  [ -f "$wf" ] || { echo "  FAIL exception ${key}: ${wf} does not exist" >&2; fail=1; }
done

echo "check-github-governance: ${checked} credential-holding job(s) checked"
[ "$fail" -eq 0 ]
