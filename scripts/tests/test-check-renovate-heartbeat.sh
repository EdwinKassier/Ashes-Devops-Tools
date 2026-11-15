#!/usr/bin/env bash
# Tests for scripts/check-renovate-heartbeat.sh with a fake `gh` on PATH.
#   bash scripts/tests/test-check-renovate-heartbeat.sh   (make test-scripts)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-renovate-heartbeat.sh"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }

mkdir -p "${workdir}/bin"
# The fake gh records every call and prints FAKE_JSON for `gh api`.
cat >"${workdir}/bin/gh" <<'F'
#!/usr/bin/env bash
echo "$*" >>"${FAKE_LOG}"
[[ "$1" == "api" ]] || exit 9
printf '%s\n' "${FAKE_JSON}"
F
chmod +x "${workdir}/bin/gh"

# item <days ago>: a one-element issues response updated that many days ago.
item() {
  jq -cn --argjson d "$1" '[{updated_at: (now - $d * 86400 | todate), html_url: "https://github.com/o/r/issues/1"}]'
}

# run <json> [args...]
run() {
  local json="$1"; shift
  : >"${workdir}/log"
  FAKE_JSON="${json}" FAKE_LOG="${workdir}/log" PATH="${workdir}/bin:${PATH}" \
    bash "${SCRIPT}" "$@" >"${workdir}/out" 2>&1
}

if run "$(item 1)" --required o/r; then ok "fresh activity passes when required"; else bad "fresh activity passes when required"; fi
grep -q 'repos/o/r/issues?state=all&creator=renovate%5Bbot%5D' "${workdir}/log" \
  && ok "reads renovate[bot] issues and PRs" || bad "reads renovate[bot] issues and PRs"
grep -q 'check-renovate-heartbeat: OK' "${workdir}/out" && ok "reports OK" || bad "reports OK"

if run "$(item 20)" --required o/r; then bad "stale activity fails when required"; else ok "stale activity fails when required"; fi
grep -q '::error::.*for 20 days' "${workdir}/out" && ok "stale error names the age" || bad "stale error names the age"

if run "$(item 20)" o/r; then ok "stale activity only warns when optional"; else bad "stale activity only warns when optional"; fi
grep -q '::warning::' "${workdir}/out" && ok "optional stale run warns" || bad "optional stale run warns"

if run '[]' --required o/r; then bad "no Renovate activity fails when required"; else ok "no Renovate activity fails when required"; fi
grep -q 'not installed or has never run' "${workdir}/out" && ok "names the missing app" || bad "names the missing app"

if run '[]' o/r; then ok "a fork without Renovate passes with a warning"; else bad "a fork without Renovate passes with a warning"; fi

if run "$(item 5)" --required --max-age-days 3 o/r; then bad "--max-age-days lowers the limit"; else ok "--max-age-days lowers the limit"; fi

if run "$(item 1)" --max-age-days x o/r; then bad "a non-numeric limit is rejected"; else ok "a non-numeric limit is rejected"; fi

# The check must only read: no gh call may use a write method.
if grep -qE -- '-X|--method|--field|-f ' "${workdir}/log"; then bad "check is read-only"; else ok "check is read-only"; fi

if [ "${failures}" -ne 0 ]; then
  echo "test-check-renovate-heartbeat: ${failures} failure(s)" >&2
  exit 1
fi
echo "test-check-renovate-heartbeat: all passed"
