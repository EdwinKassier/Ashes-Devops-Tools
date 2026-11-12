#!/usr/bin/env bash
# Tests for scripts/check-security-contact.sh with a fake `gh` on PATH.
#   bash scripts/tests/test-check-security-contact.sh   (make test-scripts)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-security-contact.sh"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }

mkdir -p "${workdir}/bin"
# The fake gh prints the value of FAKE_ENABLED for `gh api`, and records every call.
cat >"${workdir}/bin/gh" <<'F'
#!/usr/bin/env bash
echo "$*" >>"${FAKE_LOG}"
[[ "$1" == "api" ]] || exit 9
printf '%s\n' "${FAKE_ENABLED}"
F
chmod +x "${workdir}/bin/gh"

# run <enabled> [args...]
run() {
  local enabled="$1"; shift
  : >"${workdir}/log"
  FAKE_ENABLED="${enabled}" FAKE_LOG="${workdir}/log" PATH="${workdir}/bin:${PATH}" \
    bash "${SCRIPT}" "$@" >"${workdir}/out" 2>&1
}

if run true o/r; then ok "channel on passes"; else bad "channel on passes"; fi
grep -q 'private-vulnerability-reporting' "${workdir}/log" && ok "reads the setting" || bad "reads the setting"

if run false o/r; then bad "channel off fails"; else ok "channel off fails"; fi
grep -q 'OFF on o/r' "${workdir}/out" && ok "off message names the repo" || bad "off message names the repo"

if run false --warn-only o/r; then ok "--warn-only exits 0 when off"; else bad "--warn-only exits 0 when off"; fi
grep -q 'OFF on o/r' "${workdir}/out" && ok "--warn-only still warns" || bad "--warn-only still warns"

# The check must only read: no gh call may use a write method.
if grep -qE -- '-X|--method|--field|-f ' "${workdir}/log"; then bad "check is read-only"; else ok "check is read-only"; fi

printf 'test-check-security-contact: %s failed\n' "${failures}"
[[ "${failures}" -eq 0 ]]
