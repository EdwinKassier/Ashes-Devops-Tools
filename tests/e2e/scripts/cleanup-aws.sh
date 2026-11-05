#!/usr/bin/env bash
# Safety-net teardown for the AWS sandbox e2e suite (tests/e2e/aws).
#
# `terraform test` already destroys everything it created. This script runs
# afterwards (CI: `if: always()`) and deletes anything a failed or cancelled
# teardown left behind. It is scoped STRICTLY to one run: it only acts on
# resources the Resource Groups Tagging API returns for the tag
# e2e-run-id=<RUN_ID> (stamped by the provider's default_tags), plus the KMS
# aliases named "alias/e2e-<RUN_ID>-*" (aliases cannot carry tags).
#
# Usage: cleanup-aws.sh <region> <run_id>
# Exit:  0 = nothing left over; 1 = leftovers were found (and deleted) or a
#        delete failed, so a broken teardown is never silently green.
set -uo pipefail

region="${1:?region required}"
run_id="${2:?run_id required}"
export AWS_REGION="$region" AWS_DEFAULT_REGION="$region"

if ! [[ "$run_id" =~ ^[0-9a-z]{1,20}$ ]]; then
  echo "::error::Refusing to clean up: run_id '$run_id' is not a plain run identifier"
  exit 2
fi

leftovers=0
failures=0

found() {
  leftovers=$((leftovers + 1))
  echo "::warning::Leftover from run ${run_id}: $1"
}

run() {
  if ! "$@"; then
    failures=$((failures + 1))
    echo "::error::Cleanup command failed: $*"
  fi
}

# Delete every object version and delete marker, bypassing GOVERNANCE Object
# Lock retention (the archive bucket uses GOVERNANCE precisely so this works).
empty_bucket() {
  local bucket="$1" batch
  while :; do
    batch="$(aws s3api list-object-versions --bucket "$bucket" --max-items 1000 --output json |
      jq -c '{Objects: ([(.Versions // [])[], (.DeleteMarkers // [])[]] | map({Key, VersionId}) | .[:1000]), Quiet: true}')" || return 1
    [ "$(jq '.Objects | length' <<<"$batch")" -gt 0 ] || return 0
    aws s3api delete-objects --bucket "$bucket" --bypass-governance-retention --delete "$batch" >/dev/null || return 1
  done
}

delete_vpc() {
  local vpc="$1" id attempt
  for id in $(aws ec2 describe-flow-logs --filter "Name=resource-id,Values=${vpc}" --query 'FlowLogs[].FlowLogId' --output text); do
    run aws ec2 delete-flow-logs --flow-log-ids "$id"
  done
  for id in $(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=${vpc}" --query 'VpcEndpoints[].VpcEndpointId' --output text); do
    run aws ec2 delete-vpc-endpoints --vpc-endpoint-ids "$id"
  done
  for id in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${vpc}" --query 'Subnets[].SubnetId' --output text); do
    run aws ec2 delete-subnet --subnet-id "$id"
  done
  for id in $(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=${vpc}" --query 'InternetGateways[].InternetGatewayId' --output text); do
    run aws ec2 detach-internet-gateway --internet-gateway-id "$id" --vpc-id "$vpc"
    run aws ec2 delete-internet-gateway --internet-gateway-id "$id"
  done
  # Gateway-endpoint deletion is asynchronous and holds routes in the tier route
  # tables, so retry the (non-main) route tables and then the VPC briefly.
  for attempt in 1 2 3 4 5 6; do
    for id in $(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=${vpc}" --query 'RouteTables[?!(Associations[?Main])].RouteTableId' --output text); do
      aws ec2 delete-route-table --route-table-id "$id" || true
    done
    aws ec2 delete-vpc --vpc-id "$vpc" && return 0
    echo "delete-vpc ${vpc} attempt ${attempt} failed; retrying in 10s"
    sleep 10
  done
  failures=$((failures + 1))
  echo "::error::Could not delete ${vpc}"
}

echo "Scanning ${region} for run ${run_id} leftovers (tag e2e-run-id=${run_id})"

arns="$(aws resourcegroupstaggingapi get-resources \
  --tag-filters "Key=e2e-run-id,Values=${run_id}" \
  --query 'ResourceTagMappingList[].ResourceARN' --output text)" || {
  echo "::error::Tagging API query failed"
  exit 1
}

for arn in $arns; do
  case "$arn" in
    arn:aws*:s3:::*)
      bucket="${arn##*:::}"
      # The tagging index lags real deletes; skip buckets that are already gone.
      aws s3api head-bucket --bucket "$bucket" >/dev/null 2>&1 || continue
      found "S3 bucket ${bucket}"
      run empty_bucket "$bucket"
      run aws s3api delete-bucket --bucket "$bucket"
      ;;
    arn:aws*:ec2:*:vpc/*)
      vpc="${arn##*/}"
      aws ec2 describe-vpcs --vpc-ids "$vpc" >/dev/null 2>&1 || continue
      found "VPC ${vpc}"
      delete_vpc "$vpc"
      ;;
    arn:aws*:kms:*:key/*)
      state="$(aws kms describe-key --key-id "$arn" --query 'KeyMetadata.KeyState' --output text 2>/dev/null)" || continue
      # PendingDeletion is the normal post-destroy state, not a leftover.
      [ "$state" = "PendingDeletion" ] && continue
      found "KMS key ${arn} (${state})"
      run aws kms schedule-key-deletion --key-id "$arn" --pending-window-in-days 7
      ;;
    *)
      # Children (subnets, route tables, endpoints, flow logs, S3 objects) are
      # removed with their parent above; anything else is reported, not deleted.
      echo "Tagged resource still indexed (handled via its parent or already deleted): ${arn}"
      ;;
  esac
done

for alias in $(aws kms list-aliases --query "Aliases[?starts_with(AliasName, 'alias/e2e-${run_id}-')].AliasName" --output text); do
  found "KMS alias ${alias}"
  run aws kms delete-alias --alias-name "$alias"
done

echo "Run ${run_id}: ${leftovers} leftover(s), ${failures} failed delete(s)"
if [ "$leftovers" -gt 0 ] || [ "$failures" -gt 0 ]; then
  exit 1
fi
