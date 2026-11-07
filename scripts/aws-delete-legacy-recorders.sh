#!/usr/bin/env bash
# BREAK-GLASS ONLY. Delete the legacy (Terraform-managed) AWS Config recorder and
# delivery channel in each workload account, per Region, so the org-wide
# recorder StackSet (aws-organization) can create its own. Step 4 of
# docs/runbooks/aws-config-recorder-migration.md.
#
#   scripts/aws-delete-legacy-recorders.sh --accounts 111111111111,222222222222 \
#     --regions eu-west-2,eu-west-1 --role-name break-glass            # dry run
#   scripts/aws-delete-legacy-recorders.sh ... --execute                 # delete
#
# Dry run is the default: it only describes what it would delete. Run it from a
# management-account break-glass session; it assumes --role-name (the member
# break-glass role, the only principal the deny-tamper SCP and the tfc-apply
# boundary let delete recorders) in each account. The recording gap per
# account lasts until the StackSet instances are re-run (runbook step 5).
#
# Never pass the security-tooling account: it keeps its own aggregator recorder.
set -euo pipefail

ACCOUNTS=""
REGIONS=""
ROLE_NAME=""
PARTITION="aws"
EXECUTE=false

usage() {
  cat <<'EOF'
Usage: scripts/aws-delete-legacy-recorders.sh --accounts IDS --regions REGIONS --role-name NAME [--execute]

  --accounts IDS      Comma-separated 12-digit workload account IDs. Required.
  --regions REGIONS   Comma-separated Regions holding a legacy recorder. Required.
  --role-name NAME    Member-account break-glass role to assume. Required.
  --partition NAME    AWS partition (default aws).
  --execute           Delete. Without it the script is a dry run.
  -h, --help          Show this help.
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
    --accounts) need_arg "$@"; ACCOUNTS="$2"; shift 2 ;;
    --regions) need_arg "$@"; REGIONS="$2"; shift 2 ;;
    --role-name) need_arg "$@"; ROLE_NAME="$2"; shift 2 ;;
    --partition) need_arg "$@"; PARTITION="$2"; shift 2 ;;
    --execute) EXECUTE=true; shift ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
done

[[ -n "${ACCOUNTS}" ]] || die "--accounts is required"
[[ -n "${REGIONS}" ]] || die "--regions is required"
[[ -n "${ROLE_NAME}" ]] || die "--role-name is required (the member-account break-glass role)"
[[ "${ROLE_NAME}" =~ ^[A-Za-z0-9+=,.@_/-]+$ ]] || die "--role-name '${ROLE_NAME}' is not an IAM role name"
[[ "${PARTITION}" =~ ^aws(-[a-z]+)*$ ]] || die "--partition '${PARTITION}' is not an AWS partition"

IFS=',' read -r -a account_list <<<"${ACCOUNTS}"
IFS=',' read -r -a region_list <<<"${REGIONS}"
for a in "${account_list[@]}"; do
  [[ "${a}" =~ ^[0-9]{12}$ ]] || die "account '${a}' is not a 12-digit AWS account ID"
done
for r in "${region_list[@]}"; do
  [[ "${r}" =~ ^[a-z]{2}(-[a-z]+)+-[0-9]+$ ]] || die "region '${r}' is not an AWS Region name"
done

mode="DRY-RUN"
[[ "${EXECUTE}" == true ]] && mode="DELETE"
printf '%s: legacy Config recorders in %d account(s) x %d Region(s)\n' "${mode}" "${#account_list[@]}" "${#region_list[@]}"

for account in "${account_list[@]}"; do
  role_arn="arn:${PARTITION}:iam::${account}:role/${ROLE_NAME}"
  creds="$(aws sts assume-role --role-arn "${role_arn}" --role-session-name legacy-recorder-migration \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text)" ||
    die "cannot assume ${role_arn}"
  read -r key secret token <<<"${creds}"

  for region in "${region_list[@]}"; do
    # Subshell: the assumed-role credentials never leak into the next account.
    (
      export AWS_ACCESS_KEY_ID="${key}" AWS_SECRET_ACCESS_KEY="${secret}" AWS_SESSION_TOKEN="${token}"
      unset AWS_PROFILE

      recorders="$(aws configservice describe-configuration-recorders --region "${region}" \
        --query "ConfigurationRecorders[?recordingScope!='INTERNAL'].name" --output text)"
      channels="$(aws configservice describe-delivery-channels --region "${region}" \
        --query 'DeliveryChannels[].name' --output text)"
      recorders="${recorders//None/}"
      channels="${channels//None/}"

      if [[ -z "${recorders//[[:space:]]/}" && -z "${channels//[[:space:]]/}" ]]; then
        printf '  %s %s %s: no legacy recorder, skipped\n' "${mode}" "${account}" "${region}"
        exit 0
      fi

      # Stop, then delete the delivery channel, then the recorder: Config
      # rejects deleting a channel while its recorder is recording.
      for recorder in ${recorders}; do
        printf '  %s %s %s stop recorder %s\n' "${mode}" "${account}" "${region}" "${recorder}"
        if [[ "${EXECUTE}" == true ]]; then
          aws configservice stop-configuration-recorder --configuration-recorder-name "${recorder}" --region "${region}"
        fi
      done
      for channel in ${channels}; do
        printf '  %s %s %s delivery channel %s\n' "${mode}" "${account}" "${region}" "${channel}"
        if [[ "${EXECUTE}" == true ]]; then
          aws configservice delete-delivery-channel --delivery-channel-name "${channel}" --region "${region}"
        fi
      done
      for recorder in ${recorders}; do
        printf '  %s %s %s recorder %s\n' "${mode}" "${account}" "${region}" "${recorder}"
        if [[ "${EXECUTE}" == true ]]; then
          aws configservice delete-configuration-recorder --configuration-recorder-name "${recorder}" --region "${region}"
        fi
      done
    )
  done
done

if [[ "${EXECUTE}" == true ]]; then
  printf 'Done. Re-run the StackSet instances now (runbook step 5: re-apply aws-organization with tolerance 0).\n'
else
  printf 'Dry run only. Re-run with --execute to delete.\n'
fi
