#!/usr/bin/env bash
# Tests for policies/opa/tests/fixtures/scrub.jq (the plan-JSON fixture scrubber).
#   bash scripts/tests/test-scrub-jq.sh   (make test-scripts)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FILTER="${REPO_ROOT}/policies/opa/tests/fixtures/scrub.jq"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }

# Synthetic plan: top-level, nested-object and list-element sensitive values,
# a fully sensitive resource, before/prior_state copies and identifiers.
cat >"${workdir}/plan.json" <<'JSON'
{
  "format_version": "1.2",
  "prior_state": {"values": {"secret": "PRIOR-SECRET-0"}},
  "variables": {"db_password": {"value": "VAR-SECRET-0"}},
  "resource_changes": [
    {
      "address": "aws_db_instance.db",
      "mode": "managed",
      "type": "aws_db_instance",
      "name": "db",
      "change": {
        "actions": ["update"],
        "before": {"password": "BEFORE-SECRET-1"},
        "before_sensitive": {"password": true},
        "after": {
          "id": "db-123",
          "arn": "arn:aws:rds:eu-west-1:111111111111:db:db",
          "password": "TOP-SECRET-1",
          "storage_encrypted": true,
          "settings": [{"token": "NESTED-SECRET-2", "tier": "small", "kms_key_id": "key-9"}],
          "auth": {"inner": {"key": "DEEP-SECRET-3", "mode": "x"}}
        },
        "after_unknown": {"arn": false},
        "after_sensitive": {
          "password": true,
          "settings": [{"token": true}],
          "auth": {"inner": {"key": true}}
        }
      }
    },
    {
      "address": "aws_secretsmanager_secret_version.v",
      "mode": "managed",
      "type": "aws_secretsmanager_secret_version",
      "name": "v",
      "change": {"actions": ["create"], "after": {"secret_string": "WHOLE-SECRET-4"}, "after_unknown": {}, "after_sensitive": true}
    }
  ]
}
JSON

out="$(jq -c -f "${FILTER}" "${workdir}/plan.json")"

leaked=""
for s in PRIOR-SECRET-0 VAR-SECRET-0 BEFORE-SECRET-1 TOP-SECRET-1 NESTED-SECRET-2 DEEP-SECRET-3 WHOLE-SECRET-4 db-123 111111111111 key-9; do
  grep -q -- "$s" <<<"${out}" && leaked="${leaked} ${s}"
done
if [[ -z "${leaked}" ]]; then ok "no sensitive value or identifier survives"; else bad "leaked:${leaked}"; fi

if jq -e '.plan.resource_changes[0].change.after.password == "(sensitive)" and .plan.resource_changes[0].change.after.settings[0].token == "(sensitive)" and .plan.resource_changes[0].change.after.auth.inner.key == "(sensitive)" and .plan.resource_changes[1].change.after == "(sensitive)"' <<<"${out}" >/dev/null; then
  ok "sensitive paths are masked, nested and whole-object"
else
  bad "sensitive paths are masked"
fi

if jq -e '.plan.resource_changes[0].change.after.storage_encrypted == true and .plan.resource_changes[0].change.after.settings[0].tier == "small" and .plan.resource_changes[0].change.actions == ["update"] and .plan.resource_changes[0].address == "aws_db_instance.db" and .plan.resource_changes[0].mode == "managed"' <<<"${out}" >/dev/null; then
  ok "policy-read attributes and identity are kept"
else
  bad "policy-read attributes and identity are kept"
fi

if jq -e '(.plan | has("prior_state") or has("variables") | not) and ([.plan.resource_changes[].change | has("before") or has("before_sensitive") or has("after_sensitive")] | any | not) and (has("run") | not)' <<<"${out}" >/dev/null; then
  ok "before, masks, prior state, variables and run are dropped"
else
  bad "before, masks, prior state, variables and run are dropped"
fi

if [[ "${failures}" -gt 0 ]]; then
  echo "test-scrub-jq: ${failures} failure(s)" >&2
  exit 1
fi
echo "test-scrub-jq: all passed"
