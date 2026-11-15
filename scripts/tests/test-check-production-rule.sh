#!/usr/bin/env bash
# Tests for scripts/check-production-rule.sh.
#   bash scripts/tests/test-check-production-rule.sh   (make test-scripts)
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-production-rule.sh"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT
failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }

# expect <fail|pass> <description> <dir under workdir> <one HCL line>
expect() {
  local want="$1" desc="$2" dir="${workdir}/$3" line="$4"
  rm -rf "${workdir:?}/envs" "${workdir:?}/modules"
  mkdir -p "${dir}"
  printf 'locals {\n  %s\n}\n' "${line}" >"${dir}/main.tf"
  if bash "${SCRIPT}" "${workdir}/envs" "${workdir}/modules" >/dev/null 2>&1; then got=pass; else got=fail; fi
  if [[ "${got}" == "${want}" ]]; then ok "${desc}"; else bad "${desc} (wanted ${want}, got ${got})"; fi
}

mkdir -p "${workdir}/envs" "${workdir}/modules"

# Blocked: an environment name decides production.
expect fail "name regex fails" envs/x 'p = can(regex("^prod(uction)?$", var.environment))'
expect fail "substring regex fails" envs/x 'p = coalesce(x, can(regex("prod", lower(var.environment))))'
expect fail "regexall on nonprod fails" envs/x 'p = length(regexall("nonprod", var.environment)) == 0'
expect fail "equality fails" envs/x 'p = var.environment == "prod"'
expect fail "reversed inequality fails" envs/x 'p = "production" != var.environment'
expect fail "preprod equality fails" envs/x 'p = k == "preprod"'
expect fail "contains list fails" envs/x 'p = contains(["prod", "production"], k)'
expect fail "contains with name not first fails" envs/x 'p = contains(["live", "prod"], k)'
expect fail "startswith fails" envs/x 'p = startswith(k, "prod")'
expect fail "startswith with separator fails" envs/x 'p = startswith(k, "prod-")'
expect fail "endswith fails" envs/x 'p = endswith(k, "-prod")'
expect fail "strcontains fails" envs/x 'p = strcontains(k, "prod")'
expect fail "blocked check next to an allowed one fails" envs/x 'p = local.profile == "production" && var.environment == "prod"'
expect fail "Vercel exclusion is scoped to its modules" envs/x 'p = d.environment == "production"'

# Allowed: no environment name decides production.
expect pass "flag-only rule passes" envs/x 'p = try(local.env_config.is_production, null) == true'
expect pass "producer and product pass" envs/x 'p = k == "producer" || startswith(k, "product") || contains(["products"], k)'
expect pass "regex on producer passes" envs/x 'p = can(regex("^producer-", k))'
expect pass "profile comparison passes" envs/x 'p = local.profile == "production"'
expect pass "profile validation passes" envs/x 'p = var.profile == null || contains(["production", "starter"], coalesce(var.profile, "production"))'
expect pass "Vercel target in modules/vercel passes" modules/vercel/project 'p = [for d in var.domains : d if d.environment == "production"]'
expect pass "TGW segment passes" modules/aws/x 'p = alltrue([for k, s in var.spoke_attachments : contains(["prod", "nonprod"], s.segment)])'
expect pass "plain assignment passes" modules/aws/x 'segment = "prod"'

if bash "${SCRIPT}" >/dev/null 2>&1; then ok "repo passes"; else bad "repo passes"; fi
printf 'test-check-production-rule: %s failed\n' "${failures}"
[[ "${failures}" -eq 0 ]]
