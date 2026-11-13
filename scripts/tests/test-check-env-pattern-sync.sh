#!/usr/bin/env bash
# Tests for scripts/check-env-pattern-sync.sh.
#   bash scripts/tests/test-check-env-pattern-sync.sh   (make test-scripts)
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-env-pattern-sync.sh"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT
failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }

# expect <exit code> <description> <tf list> <rego list>
expect() {
  local want="$1" desc="$2" tfl="$3" regol="$4" got=0
  printf 'locals {\n  code_exec_env_pattern = "^(%s)$"\n}\n' "${tfl}" >"${workdir}/main.tf"
  # shellcheck disable=SC2016 # the backticks are literal Rego raw-string quotes.
  printf 'package x\n\nsteering_env_pattern := `^((TFC_|TF_CLI_ARGS|TFE_|TF_TOKEN_).*|%s)$`\n' "${regol}" >"${workdir}/guard.rego"
  bash "${SCRIPT}" "${workdir}/main.tf" "${workdir}/guard.rego" >/dev/null 2>&1 || got=$?
  if [[ "${got}" == "${want}" ]]; then ok "${desc}"; else bad "${desc} (wanted exit ${want}, got ${got})"; fi
}

expect 0 "identical lists pass" 'LD_[A-Z_]+|ENV|PATH' 'LD_[A-Z_]+|ENV|PATH'
expect 1 "a name missing from the policy fails" 'LD_[A-Z_]+|ENV|PATH|PS4' 'LD_[A-Z_]+|ENV|PATH'
expect 1 "a name missing from tfc-admin fails" 'LD_[A-Z_]+|PATH' 'LD_[A-Z_]+|ENV|PATH'
expect 1 "a reordered list fails" 'PATH|ENV' 'ENV|PATH'

# An unreadable pattern is a setup error, not a pass.
printf 'locals {\n  other = "x"\n}\n' >"${workdir}/main.tf"
got=0; bash "${SCRIPT}" "${workdir}/main.tf" "${workdir}/guard.rego" >/dev/null 2>&1 || got=$?
if [[ "${got}" == 2 ]]; then ok "missing tfc-admin pattern exits 2"; else bad "missing tfc-admin pattern exits 2 (got ${got})"; fi

# The repository's own files agree.
if bash "${SCRIPT}" >/dev/null 2>&1; then ok "repository lists agree"; else bad "repository lists agree"; fi

if [[ "${failures}" -gt 0 ]]; then echo "test-check-env-pattern-sync: ${failures} failure(s)" >&2; exit 1; fi
echo "test-check-env-pattern-sync: all passed"
