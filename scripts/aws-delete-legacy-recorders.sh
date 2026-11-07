#!/usr/bin/env bash
# BREAK-GLASS ONLY. Delete the legacy (Terraform-managed) AWS Config recorder and
# delivery channel in each workload account, per Region, so the org-wide
# recorder StackSet (aws-organization) can create its own. Step 4 of
# docs/runbooks/aws-config-recorder-migration.md.
#
#   scripts/aws-delete-legacy-recorders.sh --accounts 111111111111,222222222222 \
#     --regions eu-west-2,eu-west-1 --role-name break-glass \
#     --exclude-account 999999999999                                   # dry run
#   scripts/aws-delete-legacy-recorders.sh ... --execute                 # delete
#
# Dry run is the default: it only describes what it would delete. Run it from a
# management-account break-glass session; it assumes --role-name (the member
# break-glass role, the only principal the deny-tamper SCP and the tfc-apply
# boundary let delete recorders) in each account. The recording gap per
# account lasts until the StackSet instances are re-run (runbook step 5).
#
# Guards:
#   * only the recorder / channel with the LEGACY names is touched
#     (--legacy-recorder-name / --legacy-channel-name, default org-recorder /
#     org-delivery); any other recorder, the StackSet's included, is left alone;
#   * a Region where a live StackSet-<stack-set-name>-* stack exists is refused
#     (the StackSet already owns recording there);
#   * --exclude-account (the security-tooling account, which keeps its own
#     aggregator recorder) is refused outright, before any AWS call.
set -euo pipefail

ACCOUNTS=""
REGIONS=""
ROLE_NAME=""
EXCLUDE_ACCOUNTS=""
PARTITION="aws"
LEGACY_RECORDER="org-recorder"
LEGACY_CHANNEL="org-delivery"
STACK_SET_NAME="org-config-recorders"
EXECUTE=false

usage() {
  cat <<'EOF'
Usage: scripts/aws-delete-legacy-recorders.sh --accounts IDS --regions REGIONS --role-name NAME
         --exclude-account IDS [options] [--execute]

  --accounts IDS               Comma-separated 12-digit workload account IDs. Required.
  --regions REGIONS            Comma-separated Regions holding a legacy recorder. Required.
  --role-name NAME             Member-account break-glass role to assume. Required.
  --exclude-account IDS        Comma-separated accounts never to touch: the security-tooling
                               account. Required; the run is refused if --accounts holds one.
  --legacy-recorder-name NAME  Legacy recorder name (default org-recorder).
  --legacy-channel-name NAME   Legacy delivery channel name (default org-delivery).
  --stack-set-name NAME        Recorder StackSet name (default org-config-recorders). A Region
                               with a live StackSet-<NAME>-* stack is refused.
  --partition NAME             AWS partition (default aws).
  --execute                    Delete. Without it the script is a dry run.
  -h, --help                   Show this help.
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
    --exclude-account) need_arg "$@"; EXCLUDE_ACCOUNTS="${EXCLUDE_ACCOUNTS:+${EXCLUDE_ACCOUNTS},}$2"; shift 2 ;;
    --legacy-recorder-name) need_arg "$@"; LEGACY_RECORDER="$2"; shift 2 ;;
    --legacy-channel-name) need_arg "$@"; LEGACY_CHANNEL="$2"; shift 2 ;;
    --stack-set-name) need_arg "$@"; STACK_SET_NAME="$2"; shift 2 ;;
    --partition) need_arg "$@"; PARTITION="$2"; shift 2 ;;
    --execute) EXECUTE=true; shift ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
done

[[ -n "${ACCOUNTS}" ]] || die "--accounts is required"
[[ -n "${REGIONS}" ]] || die "--regions is required"
[[ -n "${ROLE_NAME}" ]] || die "--role-name is required (the member-account break-glass role)"
[[ -n "${EXCLUDE_ACCOUNTS}" ]] || die "--exclude-account is required (the security-tooling account)"
[[ "${ROLE_NAME}" =~ ^[A-Za-z0-9+=,.@_/-]+$ ]] || die "--role-name '${ROLE_NAME}' is not an IAM role name"
[[ "${PARTITION}" =~ ^aws(-[a-z]+)*$ ]] || die "--partition '${PARTITION}' is not an AWS partition"
for n in "${LEGACY_RECORDER}" "${LEGACY_CHANNEL}"; do
  [[ "${n}" =~ ^[A-Za-z0-9_.-]+$ ]] || die "'${n}' is not a Config recorder / channel name"
done
[[ "${STACK_SET_NAME}" =~ ^[A-Za-z][A-Za-z0-9-]*$ ]] || die "--stack-set-name '${STACK_SET_NAME}' is not a StackSet name"

IFS=',' read -r -a account_list <<<"${ACCOUNTS}"
IFS=',' read -r -a region_list <<<"${REGIONS}"
IFS=',' read -r -a exclude_list <<<"${EXCLUDE_ACCOUNTS}"
for a in "${account_list[@]}" "${exclude_list[@]}"; do
  [[ "${a}" =~ ^[0-9]{12}$ ]] || die "account '${a}' is not a 12-digit AWS account ID"
done
for a in "${account_list[@]}"; do
  for x in "${exclude_list[@]}"; do
    [[ "${a}" != "${x}" ]] || die "account ${a} is excluded (--exclude-account): it keeps its own recorder; refusing"
  done
done
for r in "${region_list[@]}"; do
  [[ "${r}" =~ ^[a-z]{2}(-[a-z]+)+-[0-9]+$ ]] || die "region '${r}' is not an AWS Region name"
done

# Live StackSet stacks only: a failed instance's stack (ROLLBACK_COMPLETE and
# similar) is exactly what this script is here to unblock.
stack_query="Stacks[?starts_with(StackName, 'StackSet-${STACK_SET_NAME}-') && !contains(\`[\"ROLLBACK_COMPLETE\",\"ROLLBACK_FAILED\",\"CREATE_FAILED\",\"DELETE_FAILED\"]\`, StackStatus)].StackName"

mode="DRY-RUN"
[[ "${EXECUTE}" == true ]] && mode="DELETE"
printf '%s: legacy Config recorders (%s / %s) in %d account(s) x %d Region(s)\n' \
  "${mode}" "${LEGACY_RECORDER}" "${LEGACY_CHANNEL}" "${#account_list[@]}" "${#region_list[@]}"

refused=0
for account in "${account_list[@]}"; do
  role_arn="arn:${PARTITION}:iam::${account}:role/${ROLE_NAME}"
  creds="$(aws sts assume-role --role-arn "${role_arn}" --role-session-name legacy-recorder-migration \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text)" ||
    die "cannot assume ${role_arn}"
  read -r key secret token <<<"${creds}"

  for region in "${region_list[@]}"; do
    # Subshell: the assumed-role credentials never leak into the next account.
    # Exit code 3 = Region refused.
    # set +e around the subshell (not `|| rc=$?`, which would disable errexit
    # inside it); the subshell re-enables -e so any failed aws call aborts it.
    set +e
    (
      set -e
      export AWS_ACCESS_KEY_ID="${key}" AWS_SECRET_ACCESS_KEY="${secret}" AWS_SESSION_TOKEN="${token}"
      unset AWS_PROFILE

      stacks="$(aws cloudformation describe-stacks --region "${region}" --query "${stack_query}" --output text)"
      stacks="${stacks//None/}"
      if [[ -n "${stacks//[[:space:]]/}" ]]; then
        printf '  REFUSED %s %s: StackSet stack present (%s); not touching this Region\n' \
          "${account}" "${region}" "${stacks//[[:space:]]/ }" >&2
        exit 3
      fi

      recorders="$(aws configservice describe-configuration-recorders --region "${region}" \
        --query 'ConfigurationRecorders[].name' --output text)"
      channels="$(aws configservice describe-delivery-channels --region "${region}" \
        --query 'DeliveryChannels[].name' --output text)"

      has_recorder=false
      has_channel=false
      for n in ${recorders}; do [[ "${n}" == "${LEGACY_RECORDER}" ]] && has_recorder=true; done
      for n in ${channels}; do [[ "${n}" == "${LEGACY_CHANNEL}" ]] && has_channel=true; done
      for n in ${recorders} ${channels}; do
        [[ "${n}" == "${LEGACY_RECORDER}" || "${n}" == "${LEGACY_CHANNEL}" || "${n}" == "None" ]] ||
          printf '  KEEP %s %s %s (not a legacy name)\n' "${account}" "${region}" "${n}"
      done

      if [[ "${has_recorder}" == false && "${has_channel}" == false ]]; then
        printf '  %s %s %s: no legacy recorder, skipped\n' "${mode}" "${account}" "${region}"
        exit 0
      fi

      # Stop, then delete the delivery channel, then the recorder: Config
      # rejects deleting a channel while its recorder is recording.
      if [[ "${has_recorder}" == true ]]; then
        printf '  %s %s %s stop recorder %s\n' "${mode}" "${account}" "${region}" "${LEGACY_RECORDER}"
        if [[ "${EXECUTE}" == true ]]; then
          aws configservice stop-configuration-recorder --configuration-recorder-name "${LEGACY_RECORDER}" --region "${region}"
        fi
      fi
      if [[ "${has_channel}" == true ]]; then
        printf '  %s %s %s delivery channel %s\n' "${mode}" "${account}" "${region}" "${LEGACY_CHANNEL}"
        if [[ "${EXECUTE}" == true ]]; then
          aws configservice delete-delivery-channel --delivery-channel-name "${LEGACY_CHANNEL}" --region "${region}"
        fi
      fi
      if [[ "${has_recorder}" == true ]]; then
        printf '  %s %s %s recorder %s\n' "${mode}" "${account}" "${region}" "${LEGACY_RECORDER}"
        if [[ "${EXECUTE}" == true ]]; then
          aws configservice delete-configuration-recorder --configuration-recorder-name "${LEGACY_RECORDER}" --region "${region}"
        fi
      fi
    )
    rc=$?
    set -e
    if [[ "${rc}" -eq 3 ]]; then
      refused=$((refused + 1))
    elif [[ "${rc}" -ne 0 ]]; then
      die "${account} ${region}: aws call failed (exit ${rc})"
    fi
  done
done

if [[ "${refused}" -gt 0 ]]; then
  printf 'error: %d Region(s) refused (StackSet stack present); nothing was changed there.\n' "${refused}" >&2
  exit 2
fi
if [[ "${EXECUTE}" == true ]]; then
  printf 'Done. Re-run the StackSet instances now (runbook step 5: re-apply aws-organization with tolerance 0).\n'
else
  printf 'Dry run only. Re-run with --execute to delete.\n'
fi
