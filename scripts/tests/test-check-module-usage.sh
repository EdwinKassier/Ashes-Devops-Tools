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

# README cross-check: library-only labels must match the module graph.
lib_readme() { # lib_readme <tree> <table rows...>
  local tree="$1"; shift
  {
    printf '<details>\n<summary><strong>Library-only modules</strong></summary>\n\n| Module | Why |\n|---|---|\n'
    for r in "$@"; do printf '%s\n' "$r"; done
    printf '\n</details>\n'
  } >"${tree}/README.md"
}
t="$(new_tree readme_ok)"
printf '# orphan\n\n> Status: experimental\n' >"${t}/modules/orphan/README.md"
lib_readme "${t}" '| [`orphan`](modules/orphan/) | not wired |'
expect_rc "README listing exactly the unwired modules passes" 0 "${t}"

t="$(new_tree readme_wired)"
printf '# orphan\n\n> Status: experimental\n' >"${t}/modules/orphan/README.md"
lib_readme "${t}" '| [`orphan`](modules/orphan/) | x |' '| [`used`](modules/used/) | wrongly listed |'
expect_rc "README labelling a wired module library-only fails" 1 "${t}"
grep -q 'modules/used' "${workdir}/out" && ok "wired module named" || bad "wired module named"

t="$(new_tree readme_mark)"
printf '# orphan\n\n> Status: experimental\n' >"${t}/modules/orphan/README.md"
{
  printf '| [`used`](modules/used/) *(library-only)* | [`orphan`](modules/orphan/) |\n'
  printf '<summary><strong>Library-only modules</strong></summary>\n\n| Module | Why |\n|---|---|\n| [`orphan`](modules/orphan/) | x |\n</details>\n'
} >"${t}/README.md"
expect_rc "inline library-only mark on a wired module fails" 1 "${t}"

t="$(new_tree readme_missing)"
printf '# orphan\n\n> Status: experimental\n' >"${t}/modules/orphan/README.md"
lib_readme "${t}"
expect_rc "README missing an unwired module fails" 1 "${t}"

# README domain tables: header counts must equal the distinct modules linked per cloud.
domain_readme() { # domain_readme <tree> <gcp count> <aws count>
  {
    printf '<summary><strong>Library-only modules</strong></summary>\n\n| Module | Why |\n|---|---|\n| [`orphan`](modules/orphan/) | x |\n</details>\n'
    printf '### Cloud modules by domain\n\n<details>\n<summary><strong>Demo</strong> — GCP %s · AWS %s</summary>\n\n' "$2" "$3"
    printf '| Capability | Google Cloud | Amazon Web Services |\n|:--|:--|:--|\n'
    printf '| A | [`used`](modules/gcp/used/), [`orphan`](modules/gcp/orphan/) | [`x`](modules/aws/x/) |\n\n</details>\n'
  } >"$1/README.md"
}
t="$(new_tree domain_ok)"
printf '# orphan\n\n> Status: experimental\n' >"${t}/modules/orphan/README.md"
domain_readme "${t}" 2 1
sed -i.bak 's|modules/gcp/used|modules/used|; s|modules/gcp/orphan|modules/orphan|; s|modules/aws/x/|modules/used/|' "${t}/README.md"
expect_rc "domain header counts that match the table pass" 0 "${t}"

t="$(new_tree domain_stale)"
printf '# orphan\n\n> Status: experimental\n' >"${t}/modules/orphan/README.md"
domain_readme "${t}" 9 1
sed -i.bak 's|modules/gcp/used|modules/used|; s|modules/gcp/orphan|modules/orphan|; s|modules/aws/x/|modules/used/|' "${t}/README.md"
expect_rc "stale domain header count fails" 1 "${t}"
grep -q 'Demo' "${workdir}/out" && ok "stale domain named" || bad "stale domain named"

[ "${failures}" -eq 0 ] || { echo "${failures} failure(s)" >&2; exit 1; }
echo "all ok"
