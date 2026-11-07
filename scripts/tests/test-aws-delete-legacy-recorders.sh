#!/usr/bin/env bash
# Tests for scripts/aws-delete-legacy-recorders.sh, with a stubbed `aws` CLI.
#   bash scripts/tests/test-aws-delete-legacy-recorders.sh   (make test-scripts)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/aws-delete-legacy-recorders.sh"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }

# Stub aws: logs every call to $AWS_STUB_LOG.
#   AWS_STUB_RECORDERS / AWS_STUB_CHANNELS  names returned by describe-* (default
#                                           the legacy org-recorder / org-delivery)
#   AWS_STUB_EMPTY_REGION                   that Region has no recorder / channel
#   AWS_STUB_STACKSET_REGION                that Region has a live StackSet stack
#   AWS_STUB_FAIL_DELETE                    delete-* calls fail
mkdir -p "${workdir}/bin"
cat >"${workdir}/bin/aws" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${AWS_STUB_LOG}"
region=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  [[ "${args[i]}" == "--region" ]] && region="${args[i + 1]}"
done
case "$1 $2" in
  "sts assume-role")
    printf 'AKIAFAKE\tSECRETFAKE\tTOKENFAKE\n'
    ;;
  "cloudformation describe-stacks")
    if [[ "${region}" == "${AWS_STUB_STACKSET_REGION:-}" ]]; then
      printf 'StackSet-org-config-recorders-1234abcd\n'
    else
      printf '\n'
    fi
    ;;
  "configservice describe-configuration-recorders")
    if [[ "${region}" == "${AWS_STUB_EMPTY_REGION:-}" ]]; then printf '\n'; else printf '%s\n' "${AWS_STUB_RECORDERS:-org-recorder}"; fi
    ;;
  "configservice describe-delivery-channels")
    if [[ "${region}" == "${AWS_STUB_EMPTY_REGION:-}" ]]; then printf '\n'; else printf '%s\n' "${AWS_STUB_CHANNELS:-org-delivery}"; fi
    ;;
  configservice\ delete-*)
    [[ -z "${AWS_STUB_FAIL_DELETE:-}" ]] || exit 254
    ;;
  *) ;;
esac
STUB
chmod +x "${workdir}/bin/aws"
export PATH="${workdir}/bin:${PATH}"

SEC=999999999999
run_script() {
  : >"${workdir}/aws.log"
  AWS_STUB_LOG="${workdir}/aws.log" "${SCRIPT}" "$@" >"${workdir}/out.txt" 2>&1
}

# 1. Dry-run is the default: describes, never deletes.
if run_script --accounts 333333333333 --regions eu-west-2,eu-west-1 --role-name break-glass --exclude-account "${SEC}"; then
  if grep -q 'delete-\|stop-' "${workdir}/aws.log"; then
    bad "dry-run (default) must not call any stop/delete API"
  else
    ok "dry-run is the default and changes nothing"
  fi
  if grep -q 'DRY-RUN.*333333333333.*eu-west-1.*org-recorder' "${workdir}/out.txt"; then
    ok "dry-run reports what it would delete per account and region"
  else
    bad "dry-run must report the recorder it would delete"
  fi
  if grep -q 'sts assume-role --role-arn arn:aws:iam::333333333333:role/break-glass' "${workdir}/aws.log"; then
    ok "assumes the break-glass role in the target account"
  else
    bad "must assume arn:aws:iam::<account>:role/<role-name>"
  fi
else
  bad "dry-run exited non-zero: $(cat "${workdir}/out.txt")"
fi

# 2. --execute stops, deletes the channel, then the recorder, per region.
if run_script --accounts 333333333333,444444444444 --regions eu-west-2,eu-west-1 --role-name break-glass \
  --exclude-account "${SEC}" --execute; then
  deletes="$(grep -c 'configservice delete-' "${workdir}/aws.log" || true)"
  if [[ "${deletes}" == 8 ]]; then
    ok "--execute deletes one channel and one recorder per account and region"
  else
    bad "--execute expected 8 delete calls, got ${deletes}"
  fi
  first_change="$(grep -m1 'configservice \(stop\|delete\)-' "${workdir}/aws.log")"
  first_delete="$(grep -m1 'configservice delete-' "${workdir}/aws.log")"
  if [[ "${first_change}" == *"stop-configuration-recorder --configuration-recorder-name org-recorder"* &&
    "${first_delete}" == *"delete-delivery-channel --delivery-channel-name org-delivery"* ]]; then
    ok "the recorder is stopped, then the delivery channel deleted before the recorder"
  else
    bad "order must be stop, delete channel, delete recorder (got: ${first_change} / ${first_delete})"
  fi
  if grep -q 'delete-configuration-recorder --configuration-recorder-name org-recorder --region eu-west-1' "${workdir}/aws.log"; then
    ok "the recorder is deleted by name in each region"
  else
    bad "delete-configuration-recorder must name the recorder and region"
  fi
else
  bad "--execute exited non-zero: $(cat "${workdir}/out.txt")"
fi

# 3. A region without a legacy recorder is skipped.
if AWS_STUB_EMPTY_REGION=eu-west-1 run_script --accounts 333333333333 --regions eu-west-2,eu-west-1 \
  --role-name break-glass --exclude-account "${SEC}" --execute; then
  if grep -q '\(delete\|stop\)-.*--region eu-west-1' "${workdir}/aws.log"; then
    bad "a region with no recorder must not be touched"
  else
    ok "regions without a legacy recorder are skipped"
  fi
else
  bad "empty-region run exited non-zero: $(cat "${workdir}/out.txt")"
fi

# 4. Name filters: a non-legacy (StackSet) recorder / channel is never touched.
if AWS_STUB_RECORDERS=org-stackset-recorder AWS_STUB_CHANNELS=org-stackset-delivery run_script \
  --accounts 333333333333 --regions eu-west-2 --role-name break-glass --exclude-account "${SEC}" --execute; then
  if grep -q 'configservice \(stop\|delete\)-' "${workdir}/aws.log"; then
    bad "a recorder / channel without the legacy name must not be stopped or deleted"
  else
    ok "only the legacy-named recorder and channel are eligible"
  fi
else
  bad "non-legacy-name run exited non-zero: $(cat "${workdir}/out.txt")"
fi
if AWS_STUB_RECORDERS=custom-rec AWS_STUB_CHANNELS=custom-chan run_script --accounts 333333333333 --regions eu-west-2 \
  --role-name break-glass --exclude-account "${SEC}" --legacy-recorder-name custom-rec \
  --legacy-channel-name custom-chan --execute &&
  grep -q 'delete-configuration-recorder --configuration-recorder-name custom-rec' "${workdir}/aws.log" &&
  grep -q 'delete-delivery-channel --delivery-channel-name custom-chan' "${workdir}/aws.log"; then
  ok "--legacy-recorder-name / --legacy-channel-name select the names to delete"
else
  bad "--legacy-recorder-name / --legacy-channel-name must be honoured: $(cat "${workdir}/out.txt")"
fi

# 5. A region with a live StackSet stack is refused (non-zero), others proceed.
if AWS_STUB_STACKSET_REGION=eu-west-1 run_script --accounts 333333333333 --regions eu-west-2,eu-west-1 \
  --role-name break-glass --exclude-account "${SEC}" --execute; then
  bad "a region with a live StackSet stack must make the run fail"
else
  if grep -q '\(delete\|stop\)-.*--region eu-west-1' "${workdir}/aws.log"; then
    bad "the refused region must not be touched"
  elif grep -q 'REFUSED 333333333333 eu-west-1' "${workdir}/out.txt" &&
    grep -q 'delete-configuration-recorder .*--region eu-west-2' "${workdir}/aws.log"; then
    ok "a region holding a StackSet-<name>-* stack is refused; other regions proceed"
  else
    bad "refusal must be reported: $(cat "${workdir}/out.txt")"
  fi
fi

# 6. A failed aws call aborts the run.
if AWS_STUB_FAIL_DELETE=1 run_script --accounts 333333333333,444444444444 --regions eu-west-2 --role-name break-glass \
  --exclude-account "${SEC}" --execute; then
  bad "a failed delete must make the run fail"
elif grep -q '444444444444' "${workdir}/aws.log"; then
  bad "a failed delete must stop before the next account"
else
  ok "a failed aws call aborts the run"
fi

# 7. Input validation and the excluded (security-tooling) account.
if run_script --accounts 333333333333,"${SEC}" --regions eu-west-2 --role-name break-glass --exclude-account "${SEC}"; then
  bad "an excluded account in --accounts must be refused"
elif [[ -s "${workdir}/aws.log" ]]; then
  bad "the excluded-account refusal must happen before any aws call"
else
  ok "an --exclude-account (security tooling) in --accounts is refused before any aws call"
fi
if run_script --accounts 333333333333 --regions eu-west-2 --role-name break-glass; then
  bad "--exclude-account must be required"
else
  ok "--exclude-account is required"
fi
if run_script --accounts 123 --regions eu-west-2 --role-name break-glass --exclude-account "${SEC}"; then
  bad "a malformed account ID must be rejected"
else
  ok "malformed account IDs are rejected"
fi
if run_script --regions eu-west-2 --role-name break-glass --exclude-account "${SEC}"; then
  bad "--accounts must be required"
else
  ok "--accounts is required"
fi
if run_script --accounts 333333333333 --regions eu-west-2 --exclude-account "${SEC}"; then
  bad "--role-name must be required"
else
  ok "--role-name (the break-glass role) is required"
fi
if [[ -s "${workdir}/aws.log" ]]; then
  bad "invalid input must fail before any aws call"
else
  ok "invalid input fails before any aws call"
fi

if [[ "${failures}" -gt 0 ]]; then
  printf '%s failure(s)\n' "${failures}" >&2
  exit 1
fi
printf 'all aws-delete-legacy-recorders tests passed\n'
