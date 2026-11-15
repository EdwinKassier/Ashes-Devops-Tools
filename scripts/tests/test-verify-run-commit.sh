#!/usr/bin/env bash
# Tests for scripts/verify-run-commit.sh (the release-metadata workflow's check
# that the latest HCP Terraform run was built from the tagged commit).
# Fixtures in fixtures/verify-run-commit/ follow the runs API response with
# include=configuration_version.ingress_attributes.
#   bash scripts/tests/test-verify-run-commit.sh   (make test-scripts)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/verify-run-commit.sh"
FIX="${REPO_ROOT}/scripts/tests/fixtures/verify-run-commit"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }

RUN_SHA=1e1c1018d1bbc0b8517d072718e0d87c1a0eda95
OTHER_SHA=0000000000000000000000000000000000000000

# check <fixture> <tag commit>: stdout to out, stderr to err, returns the exit status
check() { TAG_COMMIT="$2" bash "${SCRIPT}" <"${FIX}/$1" >"${workdir}/out" 2>"${workdir}/err"; }

if check vcs-run.json "${RUN_SHA}" && [ "$(cat "${workdir}/out")" = "commit_match=true" ]; then
  ok "a VCS run of the tagged commit prints commit_match=true"
else
  bad "a VCS run of the tagged commit prints commit_match=true: $(cat "${workdir}/out" "${workdir}/err")"
fi

if check vcs-run.json "${OTHER_SHA}" && [ "$(cat "${workdir}/out")" = "commit_match=false" ]; then
  ok "a VCS run of another commit prints commit_match=false"
else
  bad "a VCS run of another commit prints commit_match=false: $(cat "${workdir}/out" "${workdir}/err")"
fi
grep -q "${RUN_SHA}" "${workdir}/err" && ok "the mismatch warning names the run commit" || bad "the mismatch warning names the run commit"

if check cli-run.json "${RUN_SHA}"; then
  bad "a run with no ingress attributes (CLI or API run) fails"
else
  ok "a run with no ingress attributes (CLI or API run) fails"
fi
grep -q "has no source commit" "${workdir}/err" && ok "the failure says the run has no source commit" || bad "the failure says the run has no source commit: $(cat "${workdir}/err")"
[ ! -s "${workdir}/out" ] && ok "a failure prints no commit_match output" || bad "a failure prints no commit_match output: $(cat "${workdir}/out")"

if check cv-only.json "${RUN_SHA}"; then
  bad "a response fetched without the ingress_attributes include fails"
else
  ok "a response fetched without the ingress_attributes include fails"
fi

if check unlinked-ingress.json "${RUN_SHA}"; then
  bad "ingress attributes of another configuration version do not count"
else
  ok "ingress attributes of another configuration version do not count"
fi

if TAG_COMMIT="" bash "${SCRIPT}" <"${FIX}/vcs-run.json" >/dev/null 2>&1; then
  bad "an empty TAG_COMMIT fails"
else
  ok "an empty TAG_COMMIT fails"
fi

if echo '{"data": []}' | TAG_COMMIT="${RUN_SHA}" bash "${SCRIPT}" >/dev/null 2>&1; then
  bad "a response with no run fails"
else
  ok "a response with no run fails"
fi

if echo 'not json' | TAG_COMMIT="${RUN_SHA}" bash "${SCRIPT}" >/dev/null 2>&1; then
  bad "a non-JSON response fails"
else
  ok "a non-JSON response fails"
fi

wf="${REPO_ROOT}/.github/workflows/terraform-apply.yml"
grep -q 'include=configuration_version.ingress_attributes' "${wf}" \
  && ok "the workflow requests the run's ingress attributes" \
  || bad "the workflow requests the run's ingress attributes"
grep -q 'scripts/verify-run-commit.sh' "${wf}" \
  && ok "the workflow runs scripts/verify-run-commit.sh" \
  || bad "the workflow runs scripts/verify-run-commit.sh"

printf 'test-verify-run-commit: %s failed\n' "${failures}"
[[ "${failures}" -eq 0 ]]
