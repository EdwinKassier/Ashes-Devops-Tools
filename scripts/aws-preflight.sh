#!/usr/bin/env bash
# AWS stand-up pre-flight: the organization's account quota must hold the
# management account plus every account in aws.accounts and aws.workload_accounts.
# A new organization's default quota is small (10 accounts), and aws-organization
# creates every listed account in one apply. Closed accounts keep counting
# against the quota until AWS closes them permanently.
#
#   scripts/aws-preflight.sh [--config FILE] [--quota N]   (make aws-preflight)
#
# Without --quota it asks AWS (Service Quotas, us-east-1) with management-account
# credentials and reads the applied value of the quota named
# "Maximum number of accounts". Quota codes can change, so the script looks the
# quota up by name. To use a fixed code instead, set AWS_ORG_ACCOUNT_QUOTA_CODE
# (the code AWS documented for this quota at the time of writing is L-E619E033);
# list the codes with:
#   aws service-quotas list-service-quotas --service-code organizations --region us-east-1
# Quota reference: https://docs.aws.amazon.com/organizations/latest/userguide/orgs_reference_limits.html
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${REPO_ROOT}/config/landing-zone.yaml"
QUOTA=""
QUOTA_CODE="${AWS_ORG_ACCOUNT_QUOTA_CODE:-}"
usage() { echo "usage: $0 [--config FILE] [--quota N]" >&2; exit 2; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) [[ $# -ge 2 ]] || usage; CONFIG="$2"; shift 2 ;;
    --quota) [[ $# -ge 2 ]] || usage; QUOTA="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[[ -f "${CONFIG}" ]] || { echo "aws-preflight: ${CONFIG} not found (run make init first)" >&2; exit 2; }
[[ -z "${QUOTA}" || "${QUOTA}" =~ ^[0-9]+$ ]] || { echo "aws-preflight: --quota must be a whole number, got '${QUOTA}'" >&2; exit 2; }

# Counts: "enabled", foundational accounts, workload accounts (keys at indent 4
# under aws.accounts / aws.workload_accounts; comments are ignored).
read -r enabled foundational workload < <(awk '
  /^[a-z_]+:/ { sec = $1; sub_ = ""; next }
  sec == "aws:" && /^  enabled:/ { en = $2 }
  sec == "aws:" && /^  [a-z_]+:/ { sub_ = $1; next }
  sec == "aws:" && /^    [a-z0-9_-]+:/ {
    if (sub_ == "accounts:") f++
    if (sub_ == "workload_accounts:") w++
  }
  END { print (en == "" ? "true" : en), f + 0, w + 0 }
' "${CONFIG}")

if [[ "${enabled}" != "true" ]]; then
  echo "aws-preflight: aws.enabled is false in ${CONFIG}; nothing to check."
  exit 0
fi
# aws-organization falls back to its six built-in foundational accounts when aws.accounts is empty.
if [[ "${foundational}" -eq 0 ]]; then foundational=6; fi
planned=$((foundational + workload))
required=$((planned + 1)) # + the management account

if [[ -z "${QUOTA}" ]]; then
  command -v aws >/dev/null 2>&1 || { echo "aws-preflight: the aws CLI is required without --quota" >&2; exit 2; }
  if [[ -n "${QUOTA_CODE}" ]]; then
    QUOTA="$(aws service-quotas get-service-quota --region us-east-1 --service-code organizations \
      --quota-code "${QUOTA_CODE}" --query 'Quota.Value' --output text)"
  else
    QUOTA="$(aws service-quotas list-service-quotas --region us-east-1 --service-code organizations \
      --query "Quotas[?QuotaName=='Maximum number of accounts'].Value | [0]" --output text)"
  fi
  QUOTA="${QUOTA%%.*}"
  [[ "${QUOTA}" =~ ^[0-9]+$ ]] || { echo "aws-preflight: could not read the account quota (got '${QUOTA}'); pass --quota N" >&2; exit 2; }
fi

headroom=$((QUOTA - required))
echo "aws-preflight: ${required} accounts needed (management + ${planned} in config), quota ${QUOTA}, headroom ${headroom}"
if ((headroom < 0)); then
  echo "aws-preflight: FAIL. Request an increase from the management account before applying aws-organization:" >&2
  echo "  aws service-quotas request-service-quota-increase --region us-east-1 --service-code organizations --quota-code <code of 'Maximum number of accounts'> --desired-value <n>" >&2
  exit 1
fi
if ((headroom == 0)); then
  echo "aws-preflight: WARNING: no headroom; the next workload account needs a quota increase." >&2
fi
