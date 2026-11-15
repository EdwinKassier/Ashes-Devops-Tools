#!/usr/bin/env bash
# Fail when a local-plan example tfvars file sets an identity or placement input.
# Those come from config/landing-zone.yaml and the TFC workspace variables that
# envs/tfc-admin writes. An explicit variable beats the config file, so an
# example that sets one points a fork's plan at the upstream placeholder estate.
#
#   scripts/check-example-tfvars.sh [DIR]   (default: examples/; CI via check-consistency.sh)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="${1:-${REPO_ROOT}/examples}"
FORBIDDEN='project_prefix|environment|region|default_region|terraform_admin_email|tfc_organization|organization_workspace_name|projects_workspace_name|network_hub_workspace_name|domain|billing_account|landing_zone_name|management_account_id'

hits=""
for f in "${DIR}"/*.tfvars.example; do
  [[ -e "${f}" ]] || continue
  found="$(grep -nE "^[[:space:]]*(${FORBIDDEN})[[:space:]]*=" "${f}" || true)"
  [[ -z "${found}" ]] || hits+="$(printf '%s\n' "${found}" | sed "s|^|${f#"${REPO_ROOT}/"}:|")"$'\n'
done

if [[ -n "${hits}" ]]; then
  echo "Example tfvars set inputs that config/landing-zone.yaml or tfc-admin owns:" >&2
  printf '%s' "${hits}" >&2
  echo "Remove them: an explicit variable overrides the config file." >&2
  exit 1
fi
echo "check-example-tfvars: no identity or placement inputs in example tfvars"
