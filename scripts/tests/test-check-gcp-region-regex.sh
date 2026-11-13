#!/usr/bin/env bash
# Tests for scripts/check-gcp-region-regex.sh (GCP region and zone regexes
# must accept multi-digit regions such as europe-west10).
#   bash scripts/tests/test-check-gcp-region-regex.sh   (make test-scripts)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-gcp-region-regex.sh"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }

# case <name> <file name> <line>: a directory with one file holding that line
case_dir() {
  local d="${workdir}/$1"
  rm -rf "$d"; mkdir -p "$d"
  printf '%s\n' "$3" >"${d}/$2"
  echo "$d"
}
run() { bash "${SCRIPT}" "$@" >"${workdir}/out" 2>&1; }

d=$(case_dir zone variables.tf '    condition = can(regex("^[a-z]+-[a-z]+[0-9]-[a-z]$", z))')
if run "$d"; then bad "a single-digit zone regex fails"; else ok "a single-digit zone regex fails"; fi
grep -q 'variables.tf:1:' "${workdir}/out" && ok "the failure names file and line" || bad "the failure names file and line: $(cat "${workdir}/out")"

d=$(case_dir region variables.tf '    condition = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))')
if run "$d"; then bad "a single-digit region regex fails"; else ok "a single-digit region regex fails"; fi

d=$(case_dir schema schema.json '  "pattern": "^[a-z]+-[a-z]+[0-9]-[a-z]$"')
if run "$d"; then bad "a single-digit zone pattern in a JSON schema fails"; else ok "a single-digit zone pattern in a JSON schema fails"; fi

d=$(case_dir bash init.sh '[[ "${R}" =~ ^[a-z]+-[a-z]+[0-9]$ ]] || exit 1')
if run "$d"; then bad "a single-digit region test in a script fails"; else ok "a single-digit region test in a script fails"; fi

d=$(case_dir multi variables.tf '    condition = can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", z)) && can(regex("^[a-z]+-[a-z]+[0-9]+$", r))')
if run "$d"; then ok "[0-9]+ region and zone regexes pass"; else bad "[0-9]+ region and zone regexes pass: $(cat "${workdir}/out")"; fi

d=$(case_dir aws variables.tf '    condition = can(regex("^([a-z]{2}|us-gov|eusc-[a-z]{2})-[a-z]+-[1-9][0-9]?$", var.region))')
if run "$d"; then ok "the AWS region regex is not flagged"; else bad "the AWS region regex is not flagged: $(cat "${workdir}/out")"; fi

d=$(case_dir time variables.tf '    condition = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.start_time))')
if run "$d"; then ok "a time-of-day regex is not flagged"; else bad "a time-of-day regex is not flagged"; fi

d=$(case_dir cache variables.tf 'ok')
mkdir -p "${d}/.terraform/modules/x"
printf '%s\n' 'condition = can(regex("^[a-z]+-[a-z]+[0-9]$", r))' >"${d}/.terraform/modules/x/variables.tf"
if run "$d"; then ok ".terraform directories are skipped"; else bad ".terraform directories are skipped"; fi

if (cd "${REPO_ROOT}" && run); then ok "the repository passes"; else bad "the repository passes: $(cat "${workdir}/out")"; fi

printf 'test-check-gcp-region-regex: %s failed\n' "${failures}"
[[ "${failures}" -eq 0 ]]
