#!/usr/bin/env bash
# Tests for scripts/check-examples-refs.sh.
#   bash scripts/tests/test-check-examples-refs.sh   (make test-scripts)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-examples-refs.sh"
FIXTURES="${REPO_ROOT}/scripts/tests/fixtures/examples-refs"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }

# stage <fixture.md>: a clean dir holding only that fixture.
stage() {
  rm -rf "${workdir}/d"
  mkdir -p "${workdir}/d"
  cp "${FIXTURES}/$1" "${workdir}/d/"
}

expect_pass() {
  local out
  stage "$1"
  if out="$(bash "${SCRIPT}" "${workdir}/d" 2>&1)"; then ok "$1 passes"; else bad "$1 should pass: ${out}"; fi
}
# expect_fail <fixture> <needle>: must exit non-zero and print <needle>.
expect_fail() {
  local out
  stage "$1"
  if out="$(bash "${SCRIPT}" "${workdir}/d" 2>&1)"; then
    bad "$1 should fail (checker passed)"
  elif grep -qF -- "$2" <<<"${out}" && grep -qE "$1:[0-9]+:" <<<"${out}"; then
    ok "$1 fails naming file:line and '$2'"
  else
    bad "$1 output lacks file:line or '$2': ${out}"
  fi
}

expect_pass good.md
expect_fail bad-module.md "modules/gcp/network/does-not-exist not found"
expect_fail bad-input.md "not_a_real_input not found"
expect_fail bad-yaml.md "gcp.nonexistent_key not found"
expect_pass good-nonlocal.md
expect_fail bad-heredoc.md "heredoc_bad_input not found"
expect_fail bad-second-module.md "modules/gcp/network/nope-two not found"
expect_fail bad-terraform-fence.md "modules/gcp/network/nope-tf not found"
expect_fail bad-single-line.md "modules/gcp/network/nope-single not found"
expect_fail bad-unclosed.md "unclosed module"
expect_fail bad-envs.md "envs/gcp/nowhere not found"

# Missing and empty dirs pass.
if bash "${SCRIPT}" "${workdir}/missing" >/dev/null 2>&1; then ok "missing dir passes"; else bad "missing dir should pass"; fi
mkdir -p "${workdir}/empty"
if bash "${SCRIPT}" "${workdir}/empty" >/dev/null 2>&1; then ok "empty dir passes"; else bad "empty dir should pass"; fi

if [[ ${failures} -gt 0 ]]; then
  printf '%d failure(s)\n' "${failures}" >&2
  exit 1
fi
echo "all tests passed"
