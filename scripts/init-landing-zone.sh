#!/usr/bin/env bash
# Scaffold config/landing-zone.yaml, the single-source landing-zone configuration
# every root under envs/** reads, from config/landing-zone.example.yaml.
#
# Non-interactive:
#   scripts/init-landing-zone.sh --non-interactive --org-name acme --clouds gcp,aws \
#     --domain acme.com --billing-account 0A1B2C-3D4E5F-6A7B8C \
#     --gcp-admin-email admin@acme.com --aws-management-account 123456789012
# Interactive: run with no flags from a terminal and answer the prompts.
#
# The generated file is a starting point: review it (AWS root emails, groups,
# environments, CIDRs), then commit it. Validation here mirrors the Terraform
# variable validations, so a value accepted here is accepted at plan time.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXAMPLE="${REPO_ROOT}/config/landing-zone.example.yaml"
OUTPUT="${REPO_ROOT}/config/landing-zone.yaml"

ORG_NAME=""
DISPLAY_NAME=""
PREFIX=""
DOMAIN=""
TFC_ORG=""
GCP_ORG_ID=""
BILLING_ACCOUNT=""
GCP_ADMIN_EMAIL=""
AWS_MGMT_ACCOUNT=""
GCP_REGION=""
AWS_REGION=""
CLOUDS=""
REBRAND=false
FORCE=false
INTERACTIVE=true

usage() {
  cat <<'EOF'
Usage: scripts/init-landing-zone.sh [options]

Writes config/landing-zone.yaml from config/landing-zone.example.yaml.

Options:
  --org-name NAME               Landing-zone identifier (org.name; AWS landing_zone_name).
                                2-31 chars: ^[a-z][a-z0-9-]{1,30}$. Required.
  --display-name TEXT           Human-readable organization name (org.display_name).
  --prefix PREFIX               GCP project-ID prefix (org.prefix), ^[a-z][a-z0-9-]{0,9}$.
                                Default: --org-name when it fits.
  --domain DOMAIN               Cloud Identity / Workspace domain (org.domain). Required for gcp.
  --tfc-org NAME                Terraform Cloud organization (org.tfc.organization).
                                Default: --org-name.
  --clouds LIST                 Comma-separated subset of gcp,aws,saas to enable. Required.
  --gcp-org-id ID               Numeric GCP organization ID. Informational only: the
                                roots resolve the org from --domain (written as a comment).
  --billing-account ID          GCP billing account (XXXXXX-XXXXXX-XXXXXX).
  --gcp-admin-email EMAIL       GCP organization administrator (gcp.admin_email).
  --aws-management-account ID   12-digit AWS management (payer) account ID.
  --gcp-region REGION           Default GCP region (org.regions.gcp). Default europe-west2.
  --aws-region REGION           Default AWS region (org.regions.aws). Default eu-west-2.
  --output PATH                 Output file. Default config/landing-zone.yaml.
  --rebrand                     Also replace the "Ashes DevOps Tools" title in README.md.
  --force                       Overwrite an existing output file.
  --non-interactive             Never prompt; fail on missing required values.
  -h, --help                    Show this help.
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need_arg() {
  [[ $# -ge 2 && -n "$2" ]] || die "$1 requires a value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org-name) need_arg "$@"; ORG_NAME="$2"; shift 2 ;;
    --display-name) need_arg "$@"; DISPLAY_NAME="$2"; shift 2 ;;
    --prefix) need_arg "$@"; PREFIX="$2"; shift 2 ;;
    --domain) need_arg "$@"; DOMAIN="$2"; shift 2 ;;
    --tfc-org) need_arg "$@"; TFC_ORG="$2"; shift 2 ;;
    --clouds) need_arg "$@"; CLOUDS="$2"; shift 2 ;;
    --gcp-org-id) need_arg "$@"; GCP_ORG_ID="$2"; shift 2 ;;
    --billing-account) need_arg "$@"; BILLING_ACCOUNT="$2"; shift 2 ;;
    --gcp-admin-email) need_arg "$@"; GCP_ADMIN_EMAIL="$2"; shift 2 ;;
    --aws-management-account) need_arg "$@"; AWS_MGMT_ACCOUNT="$2"; shift 2 ;;
    --gcp-region) need_arg "$@"; GCP_REGION="$2"; shift 2 ;;
    --aws-region) need_arg "$@"; AWS_REGION="$2"; shift 2 ;;
    --output) need_arg "$@"; OUTPUT="$2"; shift 2 ;;
    --rebrand) REBRAND=true; shift ;;
    --force) FORCE=true; shift ;;
    --non-interactive) INTERACTIVE=false; shift ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
done

[[ -t 0 ]] || INTERACTIVE=false
[[ -f "${EXAMPLE}" ]] || die "schema not found: ${EXAMPLE}"
if [[ -e "${OUTPUT}" && "${FORCE}" != true ]]; then
  die "${OUTPUT} already exists (use --force to overwrite)"
fi

# prompt VAR "Question" [default]: only asks when interactive and VAR is empty.
prompt() {
  local var="$1" question="$2" default="${3:-}" answer
  [[ -z "${!var}" && "${INTERACTIVE}" == true ]] || return 0
  if [[ -n "${default}" ]]; then
    read -r -p "${question} [${default}]: " answer
    answer="${answer:-${default}}"
  else
    read -r -p "${question}: " answer
  fi
  printf -v "${var}" '%s' "${answer}"
}

has_cloud() {
  [[ ",${CLOUDS}," == *",$1,"* ]]
}

prompt ORG_NAME "Landing-zone identifier (lowercase, e.g. acme)"
[[ -n "${ORG_NAME}" ]] || die "--org-name is required"
prompt CLOUDS "Clouds to enable (comma-separated: gcp,aws,saas)" "gcp"
[[ -n "${CLOUDS}" ]] || die "--clouds is required (comma-separated subset of gcp,aws,saas)"
CLOUDS="$(printf '%s' "${CLOUDS}" | tr -d ' ' | tr '[:upper:]' '[:lower:]')"
IFS=',' read -r -a cloud_list <<<"${CLOUDS}"
for c in "${cloud_list[@]}"; do
  case "${c}" in
    gcp | aws | saas) ;;
    *) die "--clouds: unknown cloud '${c}' (expected gcp, aws, saas)" ;;
  esac
done

default_prefix=""
[[ "${ORG_NAME}" =~ ^[a-z][a-z0-9-]{0,9}$ ]] && default_prefix="${ORG_NAME}"
prompt PREFIX "GCP project-ID prefix (<= 10 chars)" "${default_prefix}"
PREFIX="${PREFIX:-${default_prefix}}"
prompt DISPLAY_NAME "Organization display name" "${ORG_NAME}"
DISPLAY_NAME="${DISPLAY_NAME:-${ORG_NAME}}"
prompt TFC_ORG "Terraform Cloud organization" "${ORG_NAME}"
TFC_ORG="${TFC_ORG:-${ORG_NAME}}"

if has_cloud gcp; then
  prompt DOMAIN "GCP organization domain (e.g. acme.com)"
  prompt BILLING_ACCOUNT "GCP billing account ID (blank to fill in later)"
  prompt GCP_ADMIN_EMAIL "GCP organization admin email (blank to fill in later)"
  prompt GCP_REGION "Default GCP region" "europe-west2"
fi
if has_cloud aws; then
  prompt AWS_MGMT_ACCOUNT "AWS management account ID (12 digits, blank to fill in later)"
  prompt AWS_REGION "Default AWS region" "eu-west-2"
fi
GCP_REGION="${GCP_REGION:-europe-west2}"
AWS_REGION="${AWS_REGION:-eu-west-2}"

# ── Validation (mirrors the Terraform variable validations) ─────────────────
[[ "${ORG_NAME}" =~ ^[a-z][a-z0-9-]{1,30}$ ]] ||
  die "--org-name '${ORG_NAME}' must match ^[a-z][a-z0-9-]{1,30}$"
case "${ORG_NAME}" in ashes | my-org) die "--org-name '${ORG_NAME}' is an upstream placeholder" ;; esac
[[ -n "${PREFIX}" ]] || die "--prefix is required (--org-name is longer than 10 chars)"
[[ "${PREFIX}" =~ ^[a-z][a-z0-9-]{0,9}$ ]] ||
  die "--prefix '${PREFIX}' must match ^[a-z][a-z0-9-]{0,9}$"
[[ "${PREFIX}" != "my-org" ]] || die "--prefix 'my-org' is the upstream placeholder"
[[ "${TFC_ORG}" =~ ^[A-Za-z0-9_-]+$ ]] || die "--tfc-org '${TFC_ORG}' is not a valid TFC organization name"
[[ "${DISPLAY_NAME}" != *'"'* ]] || die "--display-name must not contain double quotes"
if has_cloud gcp; then
  [[ -n "${DOMAIN}" ]] || die "--domain is required when gcp is enabled"
fi
if [[ -n "${DOMAIN}" ]]; then
  [[ "${DOMAIN}" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]] ||
    die "--domain '${DOMAIN}' is not a valid lowercase domain"
fi
if [[ -n "${GCP_ORG_ID}" ]]; then
  [[ "${GCP_ORG_ID}" =~ ^[0-9]+$ ]] || die "--gcp-org-id must be numeric"
fi
if [[ -n "${BILLING_ACCOUNT}" ]]; then
  [[ "${BILLING_ACCOUNT}" =~ ^[0-9A-F]{6}-[0-9A-F]{6}-[0-9A-F]{6}$ ]] ||
    die "--billing-account must look like 0A1B2C-3D4E5F-6A7B8C"
fi
if [[ -n "${GCP_ADMIN_EMAIL}" ]]; then
  [[ "${GCP_ADMIN_EMAIL}" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] ||
    die "--gcp-admin-email must be a valid email address"
fi
if [[ -n "${AWS_MGMT_ACCOUNT}" ]]; then
  [[ "${AWS_MGMT_ACCOUNT}" =~ ^[0-9]{12}$ ]] || die "--aws-management-account must be a 12-digit AWS account ID"
fi
[[ "${GCP_REGION}" =~ ^[a-z]+-[a-z]+[0-9]+$ ]] || die "--gcp-region '${GCP_REGION}' is not a GCP region name"
[[ "${AWS_REGION}" =~ ^[a-z]{2}-[a-z]+-[1-9][0-9]?$ ]] || die "--aws-region '${AWS_REGION}' is not an AWS region name"

# ── Render ───────────────────────────────────────────────────────────────────
# All values are validated above to contain no sed metacharacters except '.',
# which is harmless in a replacement; escape '&', '|' and '\' anyway.
esc() {
  printf '%s' "$1" | sed -e 's/[&|\\]/\\&/g'
}

sed_args=(
  -e "s|^  name: my-org\$|  name: $(esc "${ORG_NAME}")|"
  -e "s|^  prefix: my-org\$|  prefix: $(esc "${PREFIX}")|"
  -e "s|^  display_name: My Organization\$|  display_name: \"$(esc "${DISPLAY_NAME}")\"|"
  -e "s|^    organization: my-org\$|    organization: $(esc "${TFC_ORG}")|"
  -e "s|my-org-org-log-archive|$(esc "${PREFIX}")-org-log-archive|"
  -e "s|europe-west2|$(esc "${GCP_REGION}")|g"
  -e "s|eu-west-2|$(esc "${AWS_REGION}")|g"
)
if [[ -n "${DOMAIN}" ]]; then
  sed_args+=(
    -e "s|^  domain: my-org\\.example\\.com\$|  domain: $(esc "${DOMAIN}")|"
    -e "s|@my-org\\.example\\.com|@$(esc "${DOMAIN}")|g"
  )
fi
[[ -z "${BILLING_ACCOUNT}" ]] || sed_args+=(-e "s|REPLACE_WITH_BILLING_ACCOUNT_ID|$(esc "${BILLING_ACCOUNT}")|")
[[ -z "${GCP_ADMIN_EMAIL}" ]] || sed_args+=(-e "s|REPLACE_WITH_ADMIN_EMAIL|$(esc "${GCP_ADMIN_EMAIL}")|")
[[ -z "${AWS_MGMT_ACCOUNT}" ]] || sed_args+=(-e "s|REPLACE_WITH_12_DIGIT_ID|${AWS_MGMT_ACCOUNT}|g")

tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT

# Header note, then the example with values substituted and the per-cloud
# `enabled:` flags set (tracked by the current top-level section).
{
  printf '# Generated by scripts/init-landing-zone.sh on %s from\n' "$(date -u +%Y-%m-%d)"
  printf '# config/landing-zone.example.yaml. Review every value, then commit this file.\n'
  sed "${sed_args[@]}" "${EXAMPLE}"
} | awk -v gcp="$(has_cloud gcp && echo true || echo false)" \
  -v aws="$(has_cloud aws && echo true || echo false)" \
  -v saas="$(has_cloud saas && echo true || echo false)" \
  -v org_id="${GCP_ORG_ID}" '
  /^[a-z_]+:/ { section = $1; sub(":", "", section) }
  section == "gcp" && /^  enabled: / { print "  enabled: " gcp; next }
  section == "aws" && /^  enabled: / { print "  enabled: " aws; next }
  section == "saas" && /^  enabled: / { print "  enabled: " saas; next }
  { print }
  /^gcp:$/ && org_id != "" {
    print "  # GCP organization ID " org_id " (informational: the roots resolve the org from org.domain)."
  }
' >"${tmp}"

mkdir -p "$(dirname "${OUTPUT}")"
mv "${tmp}" "${OUTPUT}"
trap - EXIT
printf 'Wrote %s\n' "${OUTPUT}"

if [[ "${REBRAND}" == true ]]; then
  readme="${REPO_ROOT}/README.md"
  if grep -q '^# Ashes DevOps Tools$' "${readme}"; then
    title="$(esc "${DISPLAY_NAME}") Landing Zone"
    sed -e "s|^# Ashes DevOps Tools\$|# ${title}|" \
      -e "s|^\\*\\*Ashes DevOps Tools\\*\\* is|**${title}** is|" "${readme}" >"${readme}.tmp"
    mv "${readme}.tmp" "${readme}"
    printf 'Rebranded %s\n' "${readme}"
  else
    printf 'README.md title already customised; not rebranded.\n'
  fi
fi

# ── Next steps ───────────────────────────────────────────────────────────────
remaining="$(grep -nE 'REPLACE_WITH_|@example\.com' "${OUTPUT}" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
cat <<EOF

Next steps:
  1. Review ${OUTPUT#"${REPO_ROOT}/"}: environments, CIDRs, admin groups,
     and (AWS) one real, unique root email per account.
EOF
if [[ -n "${remaining}" ]]; then
  printf '     Still placeholders (the plan rejects them until replaced):\n'
  printf '%s\n' "${remaining}" | sed 's/^/       line /'
fi
cat <<EOF
  2. Commit it: git add ${OUTPUT#"${REPO_ROOT}/"} && git commit -m "config: landing zone"
     (no secrets belong in it; tokens go in TFC sensitive variables).
  3. Create the tfc-admin workspace by hand once, then apply envs/tfc-admin
     (it derives every workspace from this file).
  4. Bootstrap in order: docs/guides/QUICK_START.md
     (GCP: docs/runbooks/bootstrap.md, AWS: docs/runbooks/aws-bootstrap.md).
EOF
