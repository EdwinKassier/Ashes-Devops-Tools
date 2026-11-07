#!/usr/bin/env bash
# Tests for scripts/check-module-usage.py --check, against a temp module tree.
#   bash scripts/tests/test-check-module-usage.sh   (make test-scripts)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-module-usage.py"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }

# new_tree <name>: a root that calls modules/used and holds modules/orphan.
new_tree() {
  local t="${workdir}/$1"
  mkdir -p "${t}/envs/r" "${t}/modules/used" "${t}/modules/orphan"
  printf 'module "u" {\n  source = "../../modules/used"\n}\n' >"${t}/envs/r/main.tf"
  : >"${t}/modules/used/versions.tf"
  : >"${t}/modules/orphan/versions.tf"
  printf '# used\n' >"${t}/modules/used/README.md"
  printf '# orphan\n' >"${t}/modules/orphan/README.md"
  echo "${t}"
}

# expect_rc <label> <expected rc> <tree>
expect_rc() {
  local rc=0
  MODULE_USAGE_ROOT="$3" python3 "${SCRIPT}" --check >"${workdir}/out" 2>&1 || rc=$?
  if [ "${rc}" -eq "$2" ]; then ok "$1"; else bad "$1 (rc=${rc}, want $2)"; cat "${workdir}/out" >&2; fi
}

t="$(new_tree unmarked)"
expect_rc "unmarked uncalled module fails" 1 "${t}"
grep -q 'unreferenced:  modules/orphan' "${workdir}/out" && ok "reported as unreferenced" || bad "unreferenced line missing"

t="$(new_tree marked)"
printf '# orphan\n\n> Status: experimental\n' >"${t}/modules/orphan/README.md"
expect_rc "marked module passes" 0 "${t}"
grep -q 'experimental:  modules/orphan' "${workdir}/out" && ok "reported as experimental" || bad "experimental line missing"

t="$(new_tree crlf)"
printf '# orphan\r\n\r\n> Status: experimental\r\n' >"${t}/modules/orphan/README.md"
expect_rc "CRLF marker passes" 0 "${t}"

t="$(new_tree trailing)"
printf '# orphan\n\n> Status: experimental  \t\n' >"${t}/modules/orphan/README.md"
expect_rc "trailing whitespace marker passes" 0 "${t}"

t="$(new_tree noreadme)"
rm "${t}/modules/orphan/README.md"
expect_rc "missing README fails without traceback" 1 "${t}"
if grep -q Traceback "${workdir}/out"; then bad "traceback on missing README"; else ok "no traceback"; fi

t="$(new_tree stale)"
printf '# used\n\n> Status: experimental\n' >"${t}/modules/used/README.md"
printf '# orphan\n\n> Status: experimental\n' >"${t}/modules/orphan/README.md"
expect_rc "stale marker only warns" 0 "${t}"
grep -q 'WARNING modules/used' "${workdir}/out" && ok "stale marker warned" || bad "stale warning missing"

[ "${failures}" -eq 0 ] || { echo "${failures} failure(s)" >&2; exit 1; }
echo "all ok"
