#!/usr/bin/env bash
# Tests for scripts/check-github-governance.sh (egress block on credential-holding jobs).
#   bash scripts/tests/test-check-github-governance.sh   (make test-scripts)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-github-governance.sh"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }

# wf <name> <egress policy> <credential line> : one workflow, one job.
wf() {
  local d="${workdir}/$1"
  rm -rf "$d"; mkdir -p "$d"
  cat >"${d}/w.yml" <<EOF
name: t
on: push
permissions: {}
jobs:
  j:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - name: Harden runner
        uses: step-security/harden-runner@46b06cea07f9e64621fdf066ba77ac6915163d43  # v2.22.3
        with:
          egress-policy: $2
      - name: s
        env:
          $3
        run: echo hi
  other:
    runs-on: ubuntu-latest
    steps:
      - run: echo no credential
EOF
  echo "$d"
}

# run <dir>: exit status of the guard on that directory
run() { bash "${SCRIPT}" "$1" >"${workdir}/out" 2>&1; }

d=$(wf secret-audit audit 'T: ${{ secrets.TFC_TOKEN }}')
if run "$d"; then bad "a secret with egress audit fails"; else ok "a secret with egress audit fails"; fi
grep -q 'FAIL w.yml:j ' "${workdir}/out" && ok "the failure names workflow and job" || bad "the failure names workflow and job"

d=$(wf secret-block block 'T: ${{ secrets.TFC_TOKEN }}')
if run "$d"; then ok "a secret with egress block passes"; else bad "a secret with egress block passes"; fi

d=$(wf expr-audit audit "T: \${{ secrets.TFC_TOKEN_GUARDRAILS != '' }}")
if run "$d"; then bad "a secret inside an expression with audit fails"; else ok "a secret inside an expression with audit fails"; fi

d=$(wf oidc-audit audit 'X: "1"')
awk '{print} /^      contents: read$/ {print "      id-token: write"}' "${d}/w.yml" >"${d}/w2" && mv "${d}/w2" "${d}/w.yml"
if run "$d"; then bad "id-token: write with egress audit fails"; else ok "id-token: write with egress audit fails"; fi
sed -i.bak 's/egress-policy: audit/egress-policy: block/' "${d}/w.yml" && rm -f "${d}/w.yml.bak"
if run "$d"; then ok "id-token: write with egress block passes"; else bad "id-token: write with egress block passes"; fi

d=$(wf github-token audit 'GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}')
if run "$d"; then ok "secrets.GITHUB_TOKEN alone does not need block"; else bad "secrets.GITHUB_TOKEN alone does not need block"; fi

d=$(wf comment audit '# secrets.TFC_TOKEN is not used here')
if run "$d"; then ok "a secret named only in a comment does not count"; else bad "a secret named only in a comment does not count"; fi

d=$(wf block-comment audit 'T: ${{ secrets.TFC_TOKEN }}')
sed -i.bak 's/egress-policy: audit/egress-policy: audit  # not block/' "${d}/w.yml" && rm -f "${d}/w.yml.bak"
if run "$d"; then bad "'block' in a trailing comment does not count as block"; else ok "'block' in a trailing comment does not count as block"; fi

mkdir -p "${workdir}/empty"
if run "${workdir}/empty"; then bad "an empty workflow directory fails"; else ok "an empty workflow directory fails"; fi

if run "${REPO_ROOT}/.github/workflows"; then ok "the repository workflows pass"; else bad "the repository workflows pass: $(cat "${workdir}/out")"; fi

printf 'test-check-github-governance: %s failed\n' "${failures}"
[[ "${failures}" -eq 0 ]]
