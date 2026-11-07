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
AWS_EMAIL_PATTERN=""
GITHUB_OWNER=""
SUPABASE_ORG=""
VERCEL_TEAM=""
GITHUB_REPO=""
AUDIT_BUCKET_LOCK=""
AWS_CONFIG_RECORDERS=""
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
  --aws-email-pattern PATTERN   Root-email pattern for every AWS account, with {key} replaced
                                by the account key, e.g. 'aws+{key}@acme.com'. Each address
                                must be real, unique and deliverable (plus-addressing works).
  --github-owner NAME           GitHub user/org whose Actions may deploy (aws.github_federation_owners).
  --supabase-org ID             Supabase organization ID (saas.defaults.supabase.organization_id).
  --vercel-team ID              Vercel team ID (saas.defaults.vercel.team_id).
  --github-repo OWNER/REPO      Repository of the first SaaS stack, "web" (saas.stacks.web).
  --audit-bucket-lock BOOL      true|false: irreversible WORM lock on the org audit-log bucket
                                (gcp.enable_audit_bucket_lock). Default false; prompted for
                                explicitly when interactive.
  --aws-config-recorders BOOL   true|false: greenfield second pass. true sets
                                aws.enable_org_config_recorders and
                                aws.enable_config_recorder_scp (org-wide Config recorders
                                plus the recorder SCP). Use it only once aws-security has
                                applied and no legacy recorders exist; an existing estate
                                follows docs/runbooks/aws-config-recorder-migration.md.
                                Default false.
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
    --aws-email-pattern) need_arg "$@"; AWS_EMAIL_PATTERN="$2"; shift 2 ;;
    --github-owner) need_arg "$@"; GITHUB_OWNER="$2"; shift 2 ;;
    --supabase-org) need_arg "$@"; SUPABASE_ORG="$2"; shift 2 ;;
    --vercel-team) need_arg "$@"; VERCEL_TEAM="$2"; shift 2 ;;
    --github-repo) need_arg "$@"; GITHUB_REPO="$2"; shift 2 ;;
    --audit-bucket-lock) need_arg "$@"; AUDIT_BUCKET_LOCK="$2"; shift 2 ;;
    --aws-config-recorders) need_arg "$@"; AWS_CONFIG_RECORDERS="$2"; shift 2 ;;
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
  prompt AUDIT_BUCKET_LOCK "Lock the org audit-log bucket (WORM, IRREVERSIBLE; true/false)" "false"
fi
AUDIT_BUCKET_LOCK="${AUDIT_BUCKET_LOCK:-false}"
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
if [[ -n "${AWS_EMAIL_PATTERN}" ]]; then
  [[ "${AWS_EMAIL_PATTERN}" =~ ^[A-Za-z0-9._%+-]*\{key\}[A-Za-z0-9._%+-]*@[a-z0-9.-]+\.[a-z]+$ ]] ||
    die "--aws-email-pattern must contain {key} in the local part, e.g. aws+{key}@acme.com"
  [[ "${AWS_EMAIL_PATTERN}" != *@example.com ]] || die "--aws-email-pattern must use a real, deliverable domain"
fi
if [[ -n "${GITHUB_OWNER}" ]]; then
  [[ "${GITHUB_OWNER}" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,38}$ ]] || die "--github-owner must be a GitHub user/org name"
fi
if [[ -n "${SUPABASE_ORG}" ]]; then
  [[ "${SUPABASE_ORG}" =~ ^[a-z0-9]{8,}$ ]] || die "--supabase-org must be at least 8 lowercase alphanumerics"
fi
if [[ -n "${VERCEL_TEAM}" ]]; then
  [[ "${VERCEL_TEAM}" =~ ^[A-Za-z0-9_-]+$ ]] || die "--vercel-team must be a Vercel team ID"
fi
if [[ -n "${GITHUB_REPO}" ]]; then
  [[ "${GITHUB_REPO}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "--github-repo must be OWNER/REPO"
fi
[[ "${GCP_REGION}" =~ ^[a-z]+-[a-z]+[0-9]+$ ]] || die "--gcp-region '${GCP_REGION}' is not a GCP region name"
[[ "${AWS_REGION}" =~ ^[a-z]{2}-[a-z]+-[1-9][0-9]?$ ]] || die "--aws-region '${AWS_REGION}' is not an AWS region name"

[[ "${AUDIT_BUCKET_LOCK}" == true || "${AUDIT_BUCKET_LOCK}" == false ]] ||
  die "--audit-bucket-lock must be true or false"
AWS_CONFIG_RECORDERS="${AWS_CONFIG_RECORDERS:-false}"
[[ "${AWS_CONFIG_RECORDERS}" == true || "${AWS_CONFIG_RECORDERS}" == false ]] ||
  die "--aws-config-recorders must be true or false"

# Phase-0 impersonation expiry: now + 7 days (RFC 3339 UTC). BSD date takes
# -v+7d, GNU date takes -d '+7 days'.
if PHASE0_EXPIRES_AT="$(date -u -v+7d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"; then
  :
else
  PHASE0_EXPIRES_AT="$(date -u -d '+7 days' +%Y-%m-%dT%H:%M:%SZ)"
fi

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
  -e "s|^  # phase0_admin_impersonation_expires_at: .*\$|  phase0_admin_impersonation_expires_at: \"${PHASE0_EXPIRES_AT}\"|"
  -e "s|^  # enable_audit_bucket_lock: false\$|  enable_audit_bucket_lock: ${AUDIT_BUCKET_LOCK}|"
  -e "s|^  enable_org_config_recorders: false\$|  enable_org_config_recorders: ${AWS_CONFIG_RECORDERS}|"
  -e "s|^  enable_config_recorder_scp: false\$|  enable_config_recorder_scp: ${AWS_CONFIG_RECORDERS}|"
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
if [[ -n "${AWS_EMAIL_PATTERN}" ]]; then
  # aws+<key>@example.com -> the pattern with {key} = the account key (log-archive, workload-dev, ...).
  email_lhs="${AWS_EMAIL_PATTERN%%\{key\}*}"
  email_rhs="${AWS_EMAIL_PATTERN#*\{key\}}"
  sed_args+=(-e "s|aws+\([a-z0-9-]*\)@example\.com|$(esc "${email_lhs}")\1$(esc "${email_rhs}")|g")
fi
if [[ -n "${GITHUB_OWNER}" ]]; then
  sed_args+=(
    -e "s|^  # github_federation_owners:\$|  github_federation_owners:|"
    -e "s|^  #   - my-github-org\$|    - $(esc "${GITHUB_OWNER}")|"
  )
fi
# GCP: new scaffolds start with a `platform` service team and an example `api`
# service deployed into it (gcp.environments.dev). The commented block in the
# example is uncommented; the github deploy identity stays commented (it needs
# a numeric repository_id, enable_app_deploy_wif and github_repository_owner_id).
if has_cloud gcp; then
  sed_args+=(
    -e "/^      # Application services (Cloud Run/,/^      iam_group_role_bindings:\$/{/^      #     github: /d;s|^      # \(services:\)\$|      \1|;s|^      # \(service_teams:\)\$|      \1|;s|^      #   |        |;}"
    -e "s|subnet_name: my-org-dev-vpc-private-|subnet_name: $(esc "${PREFIX}")-dev-vpc-private-|"
  )
fi
# SaaS: uncomment and fill saas.defaults / saas.stacks.web when values are given.
if has_cloud saas && [[ -n "${SUPABASE_ORG}${VERCEL_TEAM}${GITHUB_REPO}" ]]; then
  sed_args+=(
    -e "/^  # defaults:\$/,/^  #       production_branch: main\$/s|^  # |  |"
  )
  [[ -z "${SUPABASE_ORG}" ]] || sed_args+=(-e "s|REPLACE_WITH_SUPABASE_ORG_ID|$(esc "${SUPABASE_ORG}")|")
  [[ -z "${VERCEL_TEAM}" ]] || sed_args+=(-e "s|REPLACE_WITH_VERCEL_TEAM_ID|$(esc "${VERCEL_TEAM}")|")
  [[ -z "${GITHUB_REPO}" ]] || sed_args+=(-e "s|github_repo: my-org/web|github_repo: $(esc "${GITHUB_REPO}")|")
  sed_args+=(-e "s|project_name: my-org-web|project_name: $(esc "${PREFIX}")-web|g")
fi

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

# Validate against the schema when the tool is available (optional dev tool).
if command -v check-jsonschema >/dev/null 2>&1; then
  check-jsonschema --schemafile "${REPO_ROOT}/config/landing-zone.schema.json" "${OUTPUT}" ||
    {
      printf 'ERROR: %s does not match config/landing-zone.schema.json\n' "${OUTPUT}" >&2
      exit 1
    }
fi

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
# Only report placeholders in sections the plan will read (org + enabled clouds).
remaining="$(awk -v gcp="$(has_cloud gcp && echo 1 || echo 0)" -v aws="$(has_cloud aws && echo 1 || echo 0)" \
  -v saas="$(has_cloud saas && echo 1 || echo 0)" '
  /^[a-z_]+:/ { section = $1; sub(":", "", section) }
  /^[[:space:]]*#/ { next }
  /REPLACE_WITH_|@example\.com/ {
    if (section == "gcp" && !gcp) next
    if (section == "aws" && !aws) next
    if (section == "saas" && !saas) next
    print NR ":" $0
  }' "${OUTPUT}")"
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
