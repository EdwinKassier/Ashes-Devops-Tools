#!/usr/bin/env bash
# Every deployable root has a README whose terraform-docs block is current, so
# the variable reference cannot drift from variables.tf (ADO-4). The pre-commit
# hook and `make docs` must also cover the same directories.
#   bash scripts/tests/test-module-docs.sh   (make test-scripts)
# It does not run terraform-docs: the Docs Check job and `make docs-check` gate freshness.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPO_ROOT}"
failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() {
  failures=$((failures + 1))
  printf '  FAIL %s\n' "$1" >&2
}

envs="$(./scripts/terraform-roots.sh envs)"
modules="$(./scripts/terraform-roots.sh modules)"
targets="$(./scripts/docs-targets.sh)"

while IFS= read -r root; do
  if [[ -f "${root}/README.md" ]] && grep -q '<!-- BEGIN_TF_DOCS -->' "${root}/README.md"; then
    ok "${root} has a generated reference"
  else
    bad "${root} has no README with BEGIN_TF_DOCS"
  fi
done <<<"${envs}"

# The target list: exactly 15 envs roots, exactly the modules set, and the
# organization root (the one ADO-4 is about) with the envs config.
tab=$'\t'
envs_lines="$(grep -c "^\.terraform-docs-envs\.yml${tab}envs/" <<<"${targets}" || true)"
[[ "${envs_lines}" -eq 15 ]] && ok "docs-targets lists 15 envs roots" || bad "docs-targets lists ${envs_lines} envs roots, want 15"
target_modules="$(awk -F'\t' '$1 == ".terraform-docs.yml" {print $2}' <<<"${targets}")"
[[ "${target_modules}" == "${modules}" ]] && ok "docs-targets modules equal terraform-roots.sh modules" || bad "docs-targets modules differ from terraform-roots.sh modules"
grep -qxF ".terraform-docs-envs.yml${tab}envs/gcp/organization" <<<"${targets}" && ok "organization root uses the envs config" || bad "organization root missing from docs-targets"

# Behaviour: the hook ignores a path that is not a docs target.
hook_out="$(scripts/precommit-terraform-docs.sh scripts/not-a-target/x.tf 2>&1)" && hook_rc=0 || hook_rc=$?
[[ "${hook_rc}" -eq 0 && -z "${hook_out}" ]] && ok "hook ignores a non-target path" || bad "hook ignores a non-target path"

# Behaviour: the check fails, not passes vacuously, when discovery finds nothing.
# A stub repo copy would need writes, so assert on the executable guard lines.
grep -q '^if \[ -z "\$targets" \]; then' scripts/module-docs.sh && ok "module-docs fails on empty targets" || bad "module-docs fails on empty targets"
grep -q '^done <<<"\$targets"' scripts/module-docs.sh && ok "module-docs loops over captured targets" || bad "module-docs loops over captured targets"
grep -q '^targets="\$(./scripts/docs-targets.sh)"' scripts/precommit-terraform-docs.sh && ok "hook reads docs-targets.sh" || bad "hook reads docs-targets.sh"

if grep -Eq "^[[:space:]]*files: ['\"]?\^\(modules\|envs\)/" .pre-commit-config.yaml; then
  ok "pre-commit hook matches envs/ files"
else
  bad "pre-commit hook matches envs/ files"
fi

printf 'test-module-docs: %s failed\n' "${failures}"
[[ "${failures}" -eq 0 ]]
