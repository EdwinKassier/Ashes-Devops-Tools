#!/usr/bin/env bash
# Safety-net teardown for the GCP sandbox e2e suite (tests/e2e/gcp).
#
# `terraform test` already destroys everything it created. This script runs
# afterwards (CI: `if: always()`) and deletes anything a failed or cancelled
# teardown left behind. It is scoped STRICTLY to one run:
#   * labelled resources  -> label e2e-run-id=<RUN_ID>
#   * unlabelled networks -> name prefix "e2e-<RUN_ID>-" (VPCs/subnets carry no labels)
# It never touches anything else in the project.
#
# Usage: cleanup-gcp.sh <project_id> <region> <run_id>
# Exit:  0 = nothing left over; 1 = leftovers were found (and deleted) or a
#        delete failed, so a broken teardown is never silently green.
set -uo pipefail

project="${1:?project_id required}"
region="${2:?region required}"
run_id="${3:?run_id required}"

if ! [[ "$run_id" =~ ^[0-9a-z]{1,20}$ ]]; then
  echo "::error::Refusing to clean up: run_id '$run_id' is not a plain run identifier"
  exit 2
fi

prefix="e2e-${run_id}-"
label_filter="labels.e2e-run-id=${run_id}"
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

echo "Scanning project ${project} (${region}) for run ${run_id} leftovers"

# Secrets (labelled).
while read -r secret; do
  [ -n "$secret" ] || continue
  found "secret ${secret}"
  run gcloud secrets delete "$secret" --project "$project" --quiet
done < <(gcloud secrets list --project "$project" --filter="$label_filter" --format='value(name.basename())')

# Buckets (labelled): every object version, then the bucket.
while read -r bucket; do
  [ -n "$bucket" ] || continue
  found "bucket gs://${bucket}"
  run gcloud storage rm --recursive --all-versions --quiet "gs://${bucket}"
done < <(gcloud storage buckets list --project "$project" --filter="$label_filter" --format='value(name)')

# Subnets, then VPCs (no label support -> run-scoped name prefix).
while read -r subnet subnet_region; do
  [ -n "$subnet" ] || continue
  found "subnet ${subnet} (${subnet_region})"
  run gcloud compute networks subnets delete "$subnet" --region "$subnet_region" --project "$project" --quiet
done < <(gcloud compute networks subnets list --project "$project" --filter="name ~ ^${prefix}" --format='value(name,region.basename())')

while read -r network; do
  [ -n "$network" ] || continue
  found "network ${network}"
  run gcloud compute networks delete "$network" --project "$project" --quiet
done < <(gcloud compute networks list --project "$project" --filter="name ~ ^${prefix}" --format='value(name)')

# KMS: keyrings can never be deleted (free); only live key versions matter.
while read -r keyring; do
  [ -n "$keyring" ] || continue
  while read -r key; do
    [ -n "$key" ] || continue
    while read -r version; do
      [ -n "$version" ] || continue
      found "KMS key version ${version}"
      run gcloud kms keys versions destroy "$version" --quiet
    done < <(gcloud kms keys versions list --key "$key" --filter='state=(ENABLED OR DISABLED)' --format='value(name)')
  done < <(gcloud kms keys list --keyring "$keyring" --filter="$label_filter" --format='value(name)')
done < <(gcloud kms keyrings list --project "$project" --location "$region" --filter="name ~ /keyRings/${prefix}" --format='value(name)')

echo "Run ${run_id}: ${leftovers} leftover(s), ${failures} failed delete(s)"
if [ "$leftovers" -gt 0 ] || [ "$failures" -gt 0 ]; then
  exit 1
fi
