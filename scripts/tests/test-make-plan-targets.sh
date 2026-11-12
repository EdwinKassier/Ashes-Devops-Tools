#!/usr/bin/env bash
# make plan-<cloud>-<root> resolves to a read-only plan of the right root, and
# the matching apply-<cloud>-<root> targets refuse (applies run in HCP Terraform).
# Each root's workspace name comes from its backend.tf, so a renamed workspace fails here.
#   bash scripts/tests/test-make-plan-targets.sh   (make test-scripts)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }

for r in bootstrap organization guardrails projects network-hub; do
  make -n "plan-gcp-${r}" | grep -q "chdir=envs/gcp/${r} plan" && ok "plan-gcp-${r}" || bad "plan-gcp-${r}"
  grep -q "name = \"gcp-${r}\"" "envs/gcp/${r}/backend.tf" && ok "envs/gcp/${r} workspace is gcp-${r}" || bad "envs/gcp/${r} workspace is gcp-${r}"
done
for r in organization security network identity shared-services backup; do
  make -n "plan-aws-${r}" | grep -q "chdir=envs/aws/${r} plan" && ok "plan-aws-${r}" || bad "plan-aws-${r}"
  grep -q "name = \"aws-${r}\"" "envs/aws/${r}/backend.tf" && ok "envs/aws/${r} workspace is aws-${r}" || bad "envs/aws/${r} workspace is aws-${r}"
done
make -n plan-aws-workload APP_ENV=dev | grep -q 'TF_WORKSPACE=aws-workload-dev .*chdir=envs/aws/workload plan' && ok "plan-aws-workload" || bad "plan-aws-workload"
make -n plan-gcp-workload APP_ENV=dev | grep -q 'TF_WORKSPACE=gcp-workload-dev .*chdir=envs/gcp/workload plan' && ok "plan-gcp-workload" || bad "plan-gcp-workload"

if make plan-aws-bogus >/dev/null 2>&1; then bad "unknown AWS root refused"; else ok "unknown AWS root refused"; fi
if make plan-gcp-bogus >/dev/null 2>&1; then bad "unknown GCP root refused"; else ok "unknown GCP root refused"; fi

# Plan targets must never apply.
for t in plan-gcp-projects plan-aws-network plan-aws-workload; do
  if make -n "${t}" | grep -Eq '(terraform|\$\(TERRAFORM\)) .*\bapply\b'; then bad "${t} does not apply"; else ok "${t} does not apply"; fi
done
# Apply targets refuse for every root, not only the two with explicit rules.
for t in apply-gcp-bootstrap apply-gcp-guardrails apply-gcp-projects apply-gcp-network-hub apply-aws-organization apply-aws-network apply-aws-workload; do
  if out="$(make "${t}" 2>&1)"; then bad "${t} refuses"; elif grep -q 'Local apply is not supported' <<<"${out}"; then ok "${t} refuses"; else bad "${t} refuses with a message"; fi
done
make help | grep -q 'plan-aws-%' && ok "help lists plan-aws-%" || bad "help lists plan-aws-%"
make help | grep -q 'plan-gcp-%' && ok "help lists plan-gcp-%" || bad "help lists plan-gcp-%"
make help | grep -q 'plan-aws-workload' && ok "help lists plan-aws-workload" || bad "help lists plan-aws-workload"
printf 'test-make-plan-targets: %s failed\n' "${failures}"
[[ "${failures}" -eq 0 ]]
