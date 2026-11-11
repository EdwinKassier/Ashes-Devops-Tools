#!/usr/bin/env bash
# Every CI gate that can run on a workstation must be a make target that
# `make ci` runs.
#   bash scripts/tests/test-make-ci-parity.sh   (make test-scripts)
#
# Deliberately CI-only: the sharded validate/test matrices (make validate-all and
# make test cover the same set), SARIF upload, harden-runner and the Validation
# Summary gate. zizmor is not a CI gate yet, so it has no make target.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ci_block="$(awk '/^ci:/{f=1;next} f&&/^[^\t]/{f=0} f' "${REPO_ROOT}/Makefile")"
failures=0
for target in fmt-check consistency yamllint markdownlint-check commit-check codeowners-check \
  scaffold-fixtures-check config-check count-check links examples-refs required-checks \
  backend-check shellcheck test-scripts docs-check validate-all lint test \
  opa-test security; do
  # Anchored: a commented-out recipe line must not count.
  if grep -Eq "^[[:space:]]*@\\\$\\(MAKE\\) ${target}\$" <<<"${ci_block}"; then
    printf '  ok   make ci runs %s\n' "${target}"
  else
    printf '  FAIL make ci does not run %s\n' "${target}" >&2
    failures=$((failures + 1))
  fi
done
exit "${failures}"
