#!/usr/bin/env bash
# Tests for scripts/check-contracts.sh.
#   bash scripts/tests/test-check-contracts.sh   (make test-scripts)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-contracts.sh"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }

# expect_fail <name> <needle>: the checker run on ${workdir}/repo must fail and
# print <needle>.
expect_fail() {
  local out
  if out="$(CONTRACT_PRODUCERS="envs/aws/organization" "${SCRIPT}" "${workdir}/repo" 2>&1)"; then
    bad "$1 (checker passed)"
  elif grep -qF -- "$2" <<<"${out}"; then
    ok "$1"
  else
    bad "$1 (output lacks '$2'): ${out}"
  fi
}
expect_pass() {
  local out
  if out="$(CONTRACT_PRODUCERS="envs/aws/organization" "${SCRIPT}" "${workdir}/repo" 2>&1)"; then
    ok "$1"
  else
    bad "$1: ${out}"
  fi
}

# A minimal good tree: one producer with a contract output, two consumers of it
# with identical contract variable types.
reset_fixture() {
  rm -rf "${workdir}/repo"
  mkdir -p "${workdir}/repo/envs/aws/organization" "${workdir}/repo/envs/aws/a" "${workdir}/repo/envs/aws/b"
  cat >"${workdir}/repo/envs/aws/organization/outputs.tf" <<'EOF'
output "contract" {
  description = "Cross-root contract."
  value       = local.contract
}
EOF
  for r in a b; do
    cat >"${workdir}/repo/envs/aws/${r}/variables.tf" <<'EOF'
variable "organization_contract" {
  description = "x"
  type = object({
    account_ids = map(string)
  })
  default = null
}
EOF
    cat >"${workdir}/repo/envs/aws/${r}/main.tf" <<'EOF'
locals {
  # data.terraform_remote_state.org[0].outputs.account_ids is fine in a comment
  org_remote = local.read ? try(data.terraform_remote_state.org[0].outputs.contract, data.terraform_remote_state.org[0].outputs) : null
  ids        = data.terraform_remote_state.org[0].outputs.contract.account_ids
  bridge     = data.terraform_remote_state.saas[0].outputs.supabase_api_url
}
EOF
  done
}

if "${SCRIPT}" >/dev/null 2>&1; then ok "real repo passes"; else bad "real repo passes"; fi

reset_fixture
expect_pass "good fixture passes"

reset_fixture
printf 'locals {\n  x = data.terraform_remote_state.org[0].outputs.account_ids\n}\n' >>"${workdir}/repo/envs/aws/a/main.tf"
expect_fail "consumer reading outputs.<key> fails" "envs/aws/a/main.tf"

reset_fixture
printf 'locals {\n  x = data.terraform_remote_state.org[0].outputs\n}\n' >>"${workdir}/repo/envs/aws/b/main.tf"
expect_fail "consumer reading bare outputs fails" "envs/aws/b/main.tf"

reset_fixture
printf 'locals {\n  x = try(data.tfe_outputs.org[0].nonsensitive_values.tfc_plan_role_arns, {})\n}\n' >>"${workdir}/repo/envs/aws/a/main.tf"
expect_fail "tfe_outputs reading a key other than contract fails" "nonsensitive_values.tfc_plan_role_arns"

reset_fixture
printf 'locals {\n  x = try(data.tfe_outputs.org[0].nonsensitive_values.contract, data.tfe_outputs.org[0].nonsensitive_values, {})\n}\n' >>"${workdir}/repo/envs/aws/a/main.tf"
expect_pass "tfe_outputs contract with legacy fallback passes"

reset_fixture
printf 'locals {\n  x = try(data.terraform_remote_state.org[0].outputs.contract, data.terraform_remote_state.net[0].outputs)\n}\n' >>"${workdir}/repo/envs/aws/a/main.tf"
expect_fail "legacy fallback to a different upstream fails" "terraform_remote_state.net[0].outputs"

reset_fixture
printf 'locals {\n  x = data.terraform_remote_state.org[0].outputs["account_ids"]\n}\n' >>"${workdir}/repo/envs/aws/a/main.tf"
expect_fail "bracket read outputs[\"key\"] fails" "terraform_remote_state.org[0].outputs["

reset_fixture
rm "${workdir}/repo/envs/aws/organization/outputs.tf"
printf 'output "account_ids" {\n  value = {}\n}\n' >"${workdir}/repo/envs/aws/organization/outputs.tf"
expect_fail "producer without a contract output fails" "envs/aws/organization"

reset_fixture
cat >"${workdir}/repo/envs/aws/organization/outputs.tf" <<'EOF'
output "contract" {
  value     = local.contract
  sensitive = true
}
EOF
expect_fail "sensitive contract output fails" "sensitive"

# Mismatch fixture: two consumers of the same upstream with different types.
reset_fixture
cat >"${workdir}/repo/envs/aws/b/variables.tf" <<'EOF'
variable "organization_contract" {
  description = "x"
  type = object({
    account_ids     = map(string)
    organization_id = string
  })
  default = null
}
EOF
expect_fail "contract variable type mismatch fails" "organization_contract"

printf 'test-check-contracts: %s failed\n' "${failures}"
[[ "${failures}" -eq 0 ]]
