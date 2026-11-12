#!/usr/bin/env bash
# Tests for scripts/aws-preflight.sh (offline: --quota).
#   bash scripts/tests/test-aws-preflight.sh   (make test-scripts)
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/aws-preflight.sh"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT
failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }

cfg="${workdir}/lz.yaml"
cat >"${cfg}" <<'YAML'
org:
  name: acme
aws:
  enabled: true
  # accounts:
  #   commented_out: {email: z@acme.io, ou: Security}
  accounts:
    log_archive: {email: a@acme.io, ou: Security}
    security_tooling: {email: b@acme.io, ou: Security}
    network: {email: c@acme.io, ou: Infrastructure}
    shared_services: {email: d@acme.io, ou: Infrastructure}
    backup: {email: e@acme.io, ou: Infrastructure}
    forensics:
      email: f@acme.io
      ou: Security
  workload_accounts:
    workload_dev: {email: g@acme.io, ou: Workloads}
    workload_prod: {email: h@acme.io, ou: Workloads}
  workload_environments:
    dev:
      account_key: workload_dev
gcp:
  enabled: true
  accounts:
    not_an_aws_account: {email: x@acme.io}
YAML

# expect <label> <rc> <args...>: run against ${cfg} unless the args name another --config.
expect() {
  local label="$1" want="$2" rc=0
  shift 2
  bash "${SCRIPT}" "$@" >"${workdir}/out" 2>&1 || rc=$?
  if [[ "${rc}" -eq "${want}" ]]; then ok "${label}"; else
    bad "${label} (rc=${rc}, want ${want})"
    cat "${workdir}/out" >&2
  fi
}
has() { grep -q -- "$1" "${workdir}/out" && ok "$2" || bad "$2"; }

expect "9 accounts fit a quota of 10" 0 --config "${cfg}" --quota 10
has 'headroom 1' "headroom reported"
has '9 accounts needed' "count is management + 8 (gcp accounts and comments ignored)"
expect "9 accounts exceed a quota of 8" 1 --config "${cfg}" --quota 8
has 'request-service-quota-increase' "failure names the increase command"
expect "no headroom warns but passes" 0 --config "${cfg}" --quota 9
has 'WARNING' "no-headroom warning"

expect "a non-numeric quota is refused" 2 --config "${cfg}" --quota ten
expect "a missing config is refused" 2 --config "${workdir}/none.yaml" --quota 10
expect "an unknown argument is refused" 2 --config "${cfg}" --bogus
expect "--quota needs a value" 2 --config "${cfg}" --quota

# Without aws.accounts the root creates its six built-in foundational accounts.
cfg2="${workdir}/lz-default.yaml"
printf 'aws:\n  enabled: true\n  workload_accounts:\n    workload_dev: {email: g@acme.io, ou: Workloads}\n' >"${cfg2}"
expect "default foundational accounts are counted" 0 --config "${cfg2}" --quota 10
has '8 accounts needed' "management + 6 default + 1 workload"

cfg3="${workdir}/lz-off.yaml"
printf 'aws:\n  enabled: false\n  accounts:\n    a: {email: a@acme.io, ou: Security}\n' >"${cfg3}"
expect "a disabled AWS cloud skips the check" 0 --config "${cfg3}" --quota 1
has 'aws.enabled is false' "skip is explained"

printf 'test-aws-preflight: %s failed\n' "${failures}"
[[ "${failures}" -eq 0 ]]
