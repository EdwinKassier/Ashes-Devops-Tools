#!/usr/bin/env bash
# Tests for scripts/check-docs-counts.sh against a temp tree.
#   bash scripts/tests/test-check-docs-counts.sh   (make test-scripts)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }

# new_tree <name> <readme-tagline>: one GCP module, one GCP root, no suites.
new_tree() {
  local t="${workdir}/$1"
  mkdir -p "${t}/scripts" "${t}/modules/gcp/x" "${t}/envs/gcp/a"
  cp "${REPO_ROOT}/scripts/check-docs-counts.sh" "${REPO_ROOT}/scripts/terraform-roots.sh" "${t}/scripts/"
  : >"${t}/modules/gcp/x/versions.tf"
  : >"${t}/envs/gcp/a/main.tf"
  {
    printf '%s\n' "$2"
    printf 'badge/modules-1- badge/test_suites-0-\n'
    printf '1 modules \xe2\x80\x94 **1 GCP \xc2\xb7 0 AWS \xc2\xb7 0 SaaS \xc2\xb7 0 TFC**\n'
    printf 'envs/gcp/*<br/>1 roots\nenvs/aws/*<br/>0 layered roots\n'
    printf 'make ci-quick\n'
  } >"${t}/README.md"
  printf '1 modules, 1 deployable roots\nmake ci-quick\n' >"${t}/CLAUDE.md"
  mkdir -p "${t}/docs/guides"
  printf '`make ci-quick`\n' >"${t}/docs/guides/QUICK_START.md"
  echo "${t}"
}

run() { bash "$1/scripts/check-docs-counts.sh" >"${workdir}/out" 2>&1; }

t="$(new_tree good '**Reference Terraform landing zone (pre-production)**')"
if run "${t}"; then ok "honest README passes"; else bad "honest README passes"; cat "${workdir}/out" >&2; fi

t="$(new_tree prodgrade '**Production-grade Terraform infrastructure**')"
if run "${t}"; then bad "Production-grade claim fails"; else ok "Production-grade claim fails"; fi
grep -q 'Production-grade' "${workdir}/out" && ok "claim is named" || bad "claim is named"

t="$(new_tree fullytested 'a fully-tested platform')"
if run "${t}"; then bad "fully-tested claim fails"; else ok "fully-tested claim fails"; fi

t="$(new_tree noquick 'a reference landing zone')"
printf '1 modules, 1 deployable roots\n' >"${t}/CLAUDE.md"
if run "${t}"; then bad "CLAUDE.md without ci-quick fails"; else ok "CLAUDE.md without ci-quick fails"; fi
grep -q 'ci-quick' "${workdir}/out" && ok "missing ci-quick is named" || bad "missing ci-quick is named"

t="$(new_tree stalegcp '**Reference landing zone**')"
sed -i.bak 's|envs/gcp/\*<br/>1 roots|envs/gcp/*<br/>5 roots|' "${t}/README.md"
if run "${t}"; then bad "wrong GCP root count fails"; else ok "wrong GCP root count fails"; fi

t="$(new_tree wrongaws '**Reference landing zone**')"
sed -i.bak 's|envs/aws/\*<br/>0 layered roots|envs/aws/*<br/>7 layered roots|' "${t}/README.md"
if run "${t}"; then bad "wrong AWS root count fails"; else ok "wrong AWS root count fails"; fi

t="$(new_tree fiveroot '**Reference landing zone**')"
printf 'the five-root layer map\n' >"${t}/docs/x.md"
if run "${t}"; then bad "spelled-out stale count fails"; else ok "spelled-out stale count fails"; fi
grep -q 'docs/x.md' "${workdir}/out" && ok "stale file is named" || bad "stale file is named"

t="$(new_tree fiveroot_cap '**Reference landing zone**')"
printf '> **Five GCP roots** apply in order.\n' >"${t}/docs/x.md"
if run "${t}"; then bad "capitalised stale count fails"; else ok "capitalised stale count fails"; fi

t="$(new_tree nostale '**Reference landing zone**')"
printf 'six roots, five layered roots plus gcp-guardrails\n' >"${t}/docs/x.md"
if run "${t}"; then ok "accurate spelled-out text passes"; else bad "accurate spelled-out text passes"; cat "${workdir}/out" >&2; fi

printf 'test-check-docs-counts: %s failed\n' "${failures}"
[[ "${failures}" -eq 0 ]]
