#!/usr/bin/env bash
# check-backends.sh — prove every deployable root's backend block initialises.
#
# CI and `make validate-all` run `terraform init -backend=false`, which never
# parses the backend, so an invalid backend can sit unnoticed (it did: all 14
# roots once declared `backend "cloud"`, which Terraform rejects). This runs a
# REAL `terraform init` per root with a dummy organization and NO credentials,
# in a throwaway HOME and data dir. A correct `cloud {}` block gets as far as
# authenticating and stops at "Required token could not be found" — the pass
# condition. Any other error (unsupported backend type, invalid workspaces
# block, ...) fails the check. No network call succeeds and no state is touched.
set -euo pipefail

cd "$(dirname "$0")/.."
TERRAFORM="${TERRAFORM:-terraform}"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

fail=0
checked=0
while IFS= read -r backend; do
  root="$(dirname "$backend")"
  checked=$((checked + 1))
  ws_env=()
  # Tag-selected roots need a workspace name to resolve; any tagged name works.
  if grep -qE '^\s*tags\s*=' "$backend"; then
    ws_env=(TF_WORKSPACE="$(basename "$root")-ci")
  fi
  out="$(
    env -i PATH="$PATH" HOME="$scratch/home" \
      TF_DATA_DIR="$scratch/data/$(echo "$root" | tr / _)" \
      TF_CLOUD_ORGANIZATION=backend-check TF_IN_AUTOMATION=1 ${ws_env[@]+"${ws_env[@]}"} \
      "$TERRAFORM" -chdir="$root" init -input=false -no-color 2>&1 || true
  )"
  if grep -q "Required token could not be found" <<<"$out"; then
    echo "ok    $root"
  else
    echo "FAIL  $root"
    sed 's/^/      /' <<<"$out" | grep -v '^\s*$' | head -12
    fail=1
  fi
done < <(find envs templates -name backend.tf -not -path '*/.terraform/*' | sort)

if [ "$checked" -eq 0 ]; then
  echo "check-backends: no envs/** or templates/** backend.tf found" >&2
  exit 1
fi
if [ "$fail" -ne 0 ]; then
  echo "check-backends: at least one root's backend does not initialise" >&2
  exit 1
fi
echo "check-backends: $checked roots initialise against HCP Terraform (stopped at auth, as expected)"
