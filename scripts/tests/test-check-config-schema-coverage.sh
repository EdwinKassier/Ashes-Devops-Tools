#!/usr/bin/env bash
# Tests for scripts/check-config-schema-coverage.sh.
#   bash scripts/tests/test-check-config-schema-coverage.sh   (make test-scripts)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-config-schema-coverage.sh"
SCHEMA="${REPO_ROOT}/config/landing-zone.schema.json"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }

if "${SCRIPT}" >/dev/null 2>&1; then ok "real repo resolves"; else bad "real repo resolves"; fi

mkdir -p "${workdir}/envs/x"
printf 'locals {\n  a = try(local.lz.org.name, null)\n  b = try(local.lz.org.bogus_key, null)\n}\n' >"${workdir}/envs/x/config.tf"
if out="$("${SCRIPT}" "${SCHEMA}" "${workdir}/envs" 2>&1)"; then
  bad "unresolved path fails"
elif grep -q 'local.lz.org.bogus_key' <<<"${out}"; then
  ok "unresolved path fails and is listed"
else
  bad "unresolved path listed"
fi

printf 'locals {\n  a = try(local.lz.org.name, null)\n}\n' >"${workdir}/envs/x/config.tf"
if "${SCRIPT}" "${SCHEMA}" "${workdir}/envs" >/dev/null 2>&1; then ok "resolved path passes"; else bad "resolved path passes"; fi

printf 'test-check-config-schema-coverage: %s failed\n' "${failures}"
[[ "${failures}" -eq 0 ]]
