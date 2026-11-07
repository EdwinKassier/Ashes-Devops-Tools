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

# Stub aws: logs every call to $AWS_STUB_LOG; describe-* return one recorder /
# channel per region; sts assume-role returns fake credentials. With
# AWS_STUB_EMPTY_REGION set, that region has no recorder or channel.
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
  "configservice describe-configuration-recorders")
    if [[ "${region}" == "${AWS_STUB_EMPTY_REGION:-}" ]]; then printf '\n'; else printf 'org-recorder\n'; fi
    ;;
  "configservice describe-delivery-channels")
    if [[ "${region}" == "${AWS_STUB_EMPTY_REGION:-}" ]]; then printf '\n'; else printf 'org-delivery\n'; fi
    ;;
  *) ;;
esac
STUB
chmod +x "${workdir}/bin/aws"
export PATH="${workdir}/bin:${PATH}"

run_script() {
  : >"${workdir}/aws.log"
  AWS_STUB_LOG="${workdir}/aws.log" "${SCRIPT}" "$@" >"${workdir}/out.txt" 2>&1
}

# 1. Dry-run is the default: describes, never deletes.
if run_script --accounts 333333333333 --regions eu-west-2,eu-west-1 --role-name break-glass; then
  if grep -q 'delete-' "${workdir}/aws.log"; then
    bad "dry-run (default) must not call any delete API"
  else
    ok "dry-run is the default and deletes nothing"
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

# 2. --execute deletes the delivery channel then the recorder, per region.
if run_script --accounts 333333333333,444444444444 --regions eu-west-2,eu-west-1 --role-name break-glass --execute; then
  deletes="$(grep -c 'configservice delete-' "${workdir}/aws.log" || true)"
  if [[ "${deletes}" == 8 ]]; then
    ok "--execute deletes one channel and one recorder per account and region"
  else
    bad "--execute expected 8 delete calls, got ${deletes}"
  fi
  first_delete="$(grep -m1 'configservice delete-' "${workdir}/aws.log")"
  if [[ "${first_delete}" == *"delete-delivery-channel --delivery-channel-name org-delivery"* ]]; then
    ok "the delivery channel is deleted before the recorder"
  else
    bad "the delivery channel must be deleted first (got: ${first_delete})"
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
if AWS_STUB_EMPTY_REGION=eu-west-1 run_script --accounts 333333333333 --regions eu-west-2,eu-west-1 --role-name break-glass --execute; then
  if grep -q 'delete-.*--region eu-west-1' "${workdir}/aws.log"; then
    bad "a region with no recorder must not be touched"
  else
    ok "regions without a legacy recorder are skipped"
  fi
else
  bad "empty-region run exited non-zero: $(cat "${workdir}/out.txt")"
fi

# 4. Input validation.
if run_script --accounts 123 --regions eu-west-2 --role-name break-glass; then
  bad "a malformed account ID must be rejected"
else
  ok "malformed account IDs are rejected"
fi
if run_script --regions eu-west-2 --role-name break-glass; then
  bad "--accounts must be required"
else
  ok "--accounts is required"
fi
if run_script --accounts 333333333333 --regions eu-west-2; then
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
