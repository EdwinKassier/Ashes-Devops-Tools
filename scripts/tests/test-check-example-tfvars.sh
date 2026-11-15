#!/usr/bin/env bash
# Tests for scripts/check-example-tfvars.sh.
#   bash scripts/tests/test-check-example-tfvars.sh   (make test-scripts)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-example-tfvars.sh"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }

printf 'enable_cloud_armor = false\nterraform_admin_email = "x@y.iam.gserviceaccount.com"\n' >"${workdir}/dev.tfvars.example"
if out="$(bash "${SCRIPT}" "${workdir}" 2>&1)"; then bad "identity key fails"; else ok "identity key fails"; fi
grep -q 'terraform_admin_email' <<<"${out}" && ok "key is named" || bad "key is named"

printf '  # tfc_organization = "commented out is fine"\nenable_cloud_armor = false\n' >"${workdir}/dev.tfvars.example"
if bash "${SCRIPT}" "${workdir}" >/dev/null 2>&1; then ok "tuning-only file passes"; else bad "tuning-only file passes"; fi

if bash "${SCRIPT}" >/dev/null 2>&1; then ok "repo examples pass"; else bad "repo examples pass"; fi

printf 'test-check-example-tfvars: %s failed\n' "${failures}"
[[ "${failures}" -eq 0 ]]
