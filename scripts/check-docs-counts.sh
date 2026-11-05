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
suites="$(find modules envs -type f -name '*.tftest.hcl' ! -path '*/.terraform/*' | wc -l | tr -d ' ')"

if [ "${1:-}" = "--print" ]; then
  printf 'modules:          %s (GCP %s · AWS %s · SaaS %s · TFC %s)\n' \
    "$modules_total" "$modules_gcp" "$modules_aws" "$modules_saas" "$modules_tfc"
  printf 'deployable roots: %s\n' "$roots"
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

if [ "$fail" -ne 0 ]; then
  echo
  echo "Live counts (scripts/check-docs-counts.sh --print):"
  "$0" --print
  echo "Update README.md / CLAUDE.md to match, then re-run 'make count-check'."
  exit 1
fi
echo "check-docs-counts: README.md and CLAUDE.md counts match the tree" \
  "(${modules_total} modules, ${roots} roots, ${suites} test suites)."
