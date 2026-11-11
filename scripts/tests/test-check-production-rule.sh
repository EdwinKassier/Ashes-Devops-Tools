#!/usr/bin/env bash
# Tests for scripts/check-production-rule.sh.
#   bash scripts/tests/test-check-production-rule.sh   (make test-scripts)
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-production-rule.sh"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT
failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }

mkdir -p "${workdir}/envs/x"
printf 'locals {\n  p = can(regex("^prod(uction)?$", var.environment))\n}\n' >"${workdir}/envs/x/main.tf"
if bash "${SCRIPT}" "${workdir}/envs" >/dev/null 2>&1; then bad "name regex fails"; else ok "name regex fails"; fi

printf 'locals {\n  p = coalesce(x, can(regex("prod", lower(var.environment))))\n}\n' >"${workdir}/envs/x/main.tf"
if bash "${SCRIPT}" "${workdir}/envs" >/dev/null 2>&1; then bad "substring regex fails"; else ok "substring regex fails"; fi

printf 'locals {\n  p = try(local.env_config.is_production, null) == true\n}\n' >"${workdir}/envs/x/main.tf"
if bash "${SCRIPT}" "${workdir}/envs" >/dev/null 2>&1; then ok "flag-only rule passes"; else bad "flag-only rule passes"; fi

if bash "${SCRIPT}" >/dev/null 2>&1; then ok "repo passes"; else bad "repo passes"; fi
printf 'test-check-production-rule: %s failed\n' "${failures}"
[[ "${failures}" -eq 0 ]]
