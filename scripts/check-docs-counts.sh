#!/usr/bin/env bash
# Recompute the module / root / test-suite counts and assert that the
# hand-written figures in README.md and CLAUDE.md still match them.
#
#   scripts/check-docs-counts.sh          # check (CI: meta-lint job)
#   scripts/check-docs-counts.sh --print  # just print the live counts (make count)
#
# Canonical definitions (one place, so docs and CI cannot disagree):
#   module      = a directory under modules/ holding a versions.tf, excluding
#                 examples/, tests/ and .terraform/
#   GCP / AWS   = modules under modules/gcp/ and modules/aws/
#   SaaS        = modules under modules/supabase, modules/vercel, modules/saas
#   TFC         = modules under modules/tfc
#   root        = a deployable envs/ root (scripts/terraform-roots.sh envs)
#   test suite  = a *.tftest.hcl file under modules/ or envs/
set -euo pipefail

cd "$(dirname "$0")/.."

module_dirs() {
  find modules -type f -name versions.tf \
    ! -path '*/examples/*' ! -path '*/tests/*' ! -path '*/.terraform/*' |
    sed 's#/versions.tf$##' | sort -u
}

count_prefix() {
  module_dirs | grep -cE "^modules/($1)/" || true
}

modules_total="$(module_dirs | wc -l | tr -d ' ')"
modules_gcp="$(count_prefix gcp)"
modules_aws="$(count_prefix aws)"
modules_saas="$(count_prefix 'supabase|vercel|saas')"
modules_tfc="$(count_prefix tfc)"
roots="$(./scripts/terraform-roots.sh envs | wc -l | tr -d ' ')"
gcp_roots="$(./scripts/terraform-roots.sh envs | grep -c '^envs/gcp/' || true)"
aws_roots="$(./scripts/terraform-roots.sh envs | grep -c '^envs/aws/' || true)"
suites="$(find modules envs -type f -name '*.tftest.hcl' ! -path '*/.terraform/*' | wc -l | tr -d ' ')"

if [ "${1:-}" = "--print" ]; then
  printf 'modules:          %s (GCP %s · AWS %s · SaaS %s · TFC %s)\n' \
    "$modules_total" "$modules_gcp" "$modules_aws" "$modules_saas" "$modules_tfc"
  printf 'deployable roots: %s\n' "$roots"
  printf 'gcp roots: %s, aws roots: %s\n' "$gcp_roots" "$aws_roots"
  printf 'test suites:      %s\n' "$suites"
  exit 0
fi

fail=0
expect() {
  # expect <file> <fixed-string that must appear> <human description>
  if ! grep -qF -- "$2" "$1"; then
    echo "::error file=$1::$1 is stale: expected to find \"$2\" ($3)."
    fail=1
  fi
}

expect README.md "badge/modules-${modules_total}-" "Modules badge"
expect README.md "badge/test_suites-${suites}-" "Test-suites badge"
expect README.md "${modules_total} modules — **${modules_gcp} GCP · ${modules_aws} AWS · ${modules_saas} SaaS · ${modules_tfc} TFC**" \
  "Module Library headline"
expect CLAUDE.md "${modules_total} modules, ${roots} deployable roots" "CLAUDE.md header"
expect CLAUDE.md "make ci-quick" "CLAUDE.md lists ci-quick"
expect README.md "make ci-quick" "README.md lists ci-quick"
expect docs/guides/QUICK_START.md '`make ci-quick`' "QUICK_START.md lists ci-quick"

expect README.md "envs/gcp/*<br/>${gcp_roots} roots" "GCP root count in the architecture diagram"
expect README.md "envs/aws/*<br/>${aws_roots} layered roots" "AWS root count in the architecture diagram"
# Spelled-out GCP root counts drift silently, so these phrases are banned. Write the
# digit next to a checked figure, or name the roots. Audit reports and plans quote them
# as history, so docs/audit and docs/moai are exempt.
stale="$(grep -rnEi 'five-root|five roots|(^|[^0-9])5 roots|two-root layer map|all five GCP roots|five GCP (roots|workspaces)' \
  README.md CLAUDE.md docs --include='*.md' 2>/dev/null |
  grep -vE '^docs/(audit|moai)/' | grep -vF 'envs/gcp/*<br/>' || true)"
if [ -n "$stale" ]; then
  echo "::error::Stale spelled-out GCP root count (there are ${gcp_roots} GCP roots):"
  printf '%s\n' "$stale"
  fail=1
fi

# Claims the repo cannot back until a real-cloud apply exists (docs/known-gaps.md).
# A banned phrase in README.md or CLAUDE.md fails, so it cannot creep back.
ban() {
  # ban <file> <extended regex> <why>
  local hits
  hits="$(grep -nEi -- "$2" "$1" || true)"
  if [ -n "$hits" ]; then
    echo "::error file=$1::$1 claims more than the repo can show ($3):"
    printf '%s\n' "$hits"
    fail=1
  fi
}
for f in README.md CLAUDE.md; do
  ban "$f" 'production[- ](grade|ready)|fully[- ]tested|battle[- ]tested' \
    "no root has been applied to a real organization; see docs/runbooks/production-hardening.md"
done

if [ "$fail" -ne 0 ]; then
  echo
  echo "Live counts (scripts/check-docs-counts.sh --print):"
  "$0" --print
  echo "Update README.md / CLAUDE.md to match, then re-run 'make count-check'."
  exit 1
fi
echo "check-docs-counts: README.md and CLAUDE.md counts match the tree" \
  "(${modules_total} modules, ${roots} roots, ${suites} test suites)."
