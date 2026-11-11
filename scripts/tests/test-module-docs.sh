#!/usr/bin/env bash
# Every deployable root has a README whose terraform-docs block is current, so
# the variable reference cannot drift from variables.tf (ADO-4). The pre-commit
# hook and `make docs` must also cover the same directories.
#   bash scripts/tests/test-module-docs.sh   (make test-scripts; needs terraform-docs)
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() {
  failures=$((failures + 1))
  printf '  FAIL %s\n' "$1" >&2
}

while IFS= read -r root; do
  readme="${REPO_ROOT}/${root}/README.md"
  if [[ -f "${readme}" ]] && grep -q '<!-- BEGIN_TF_DOCS -->' "${readme}"; then
    ok "${root} has a generated reference"
  else
    bad "${root} has no README with BEGIN_TF_DOCS"
  fi
done < <(cd "${REPO_ROOT}" && ./scripts/terraform-roots.sh envs)

if (cd "${REPO_ROOT}" && bash scripts/module-docs.sh check >/dev/null 2>&1); then
  ok "module-docs check passes"
else
  bad "module-docs check passes"
fi

# Both entry points read one list, so they cover the same directories.
for f in scripts/module-docs.sh scripts/precommit-terraform-docs.sh; do
  if grep -q 'docs-targets.sh' "${REPO_ROOT}/${f}"; then
    ok "${f} reads docs-targets.sh"
  else
    bad "${f} reads docs-targets.sh"
  fi
done
targets="$(cd "${REPO_ROOT}" && ./scripts/docs-targets.sh)"
if grep -q 'terraform-docs-envs.yml' <<<"${targets}"; then
  ok "envs roots are generated"
else
  bad "envs roots are generated"
fi
if grep -q "files: '^(modules|envs)/" "${REPO_ROOT}/.pre-commit-config.yaml"; then
  ok "pre-commit hook matches envs/ files"
else
  bad "pre-commit hook matches envs/ files"
fi

printf 'test-module-docs: %s failed\n' "${failures}"
[[ "${failures}" -eq 0 ]]
