#!/usr/bin/env bash
# Fail when Terraform code decides "production" from an environment's name.
# The rule: an environment is production when its is_production is true.
# config/landing-zone.schema.json requires the flag on every environment, and
# each root that reads it rejects a config entry without it, so no name-based
# fallback (regex on "prod", "^prod(uction)?$") may exist.
#
#   scripts/check-production-rule.sh [DIR...]   (default: envs modules; CI via check-consistency.sh)
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# -eq 0 ]]; then set -- "${REPO_ROOT}/envs" "${REPO_ROOT}/modules"; fi
hits="$(grep -rnE --include='*.tf' 'regex\("[^"]*prod' "$@" | grep -v '/\.terraform/' || true)"
if [[ -n "${hits}" ]]; then
  echo "Production is decided from an environment name; use is_production only:" >&2
  printf '%s\n' "${hits}" >&2
  exit 1
fi
echo "check-production-rule: no name-based production checks"
