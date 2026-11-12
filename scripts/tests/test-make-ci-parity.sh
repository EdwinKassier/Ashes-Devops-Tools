#!/usr/bin/env bash
# Every CI gate that can run on a workstation must be a make target that
# `make ci` runs, either directly or through `make ci-quick`, which `make ci`
# runs first. `make ci-quick` is the fast offline subset: it must never run a
# target that needs terraform init, pre-commit, git history or the network.
#   bash scripts/tests/test-make-ci-parity.sh   (make test-scripts)
#
# Deliberately CI-only: the sharded validate/test matrices (make validate-all and
# make test cover the same set), SARIF upload, harden-runner and the Validation
# Summary gate.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
block() { awk -v t="$1" '$0 ~ "^" t ":" {f=1;next} f&&/^[^\t]/{f=0} f' "${REPO_ROOT}/Makefile"; }
ci_block="$(block ci)"
quick_block="$(block ci-quick)"
failures=0
runs() { grep -Eq "^[[:space:]]*@\\\$\\(MAKE\\) $2\$" <<<"$1"; }

# Anchored: a commented-out recipe line must not count.
if runs "${ci_block}" ci-quick; then
  printf '  ok   make ci runs ci-quick\n'
else
  printf '  FAIL make ci does not run ci-quick\n' >&2
  failures=$((failures + 1))
fi
for target in fmt-check consistency yamllint markdownlint-check zizmor commit-check codeowners-check \
  scaffold-fixtures-check config-check count-check links examples-refs required-checks \
  backend-check shellcheck test-scripts docs-check validate-all lint test \
  opa-test security; do
  if runs "${ci_block}" "${target}" || runs "${quick_block}" "${target}"; then
    printf '  ok   make ci runs %s\n' "${target}"
  else
    printf '  FAIL make ci does not run %s\n' "${target}" >&2
    failures=$((failures + 1))
  fi
done
# ci-quick is the offline subset: these need init, pre-commit, git history or the network.
for target in validate-all lint test security backend-check opa-test yamllint markdownlint-check \
  zizmor commit-check codeowners-check; do
  if runs "${quick_block}" "${target}"; then
    printf '  FAIL make ci-quick runs %s, which is not an offline gate\n' "${target}" >&2
    failures=$((failures + 1))
  else
    printf '  ok   make ci-quick leaves out %s\n' "${target}"
  fi
done
printf 'test-make-ci-parity: %s failed\n' "${failures}"
[[ "${failures}" -eq 0 ]]
