#!/usr/bin/env bash
# Tests for scripts/check-module-api.sh against throwaway git repositories in a
# temp dir (never this repository's history).
#   bash scripts/tests/test-check-module-api.sh   (make test-scripts)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-module-api.sh"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }

# The fixture repository must not inherit hooks, templates or signing from the
# caller's git configuration.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

# fixture <name>: a repository whose main branch has modules/m with variable a
# and b and output x, and a checked-out branch `pr` at the same commit.
fixture() {
  local d="${workdir}/$1"
  git init -q -b main "${d}"
  git -C "${d}" config user.email t@example.com
  git -C "${d}" config user.name test
  mkdir -p "${d}/modules/m/tests" "${d}/modules/other"
  printf 'variable "a" {\n  type = string\n}\n\nvariable "b" {\n  type = string\n}\n' >"${d}/modules/m/variables.tf"
  printf 'output "x" {\n  value = var.a\n}\n' >"${d}/modules/m/outputs.tf"
  printf 'variable "o" {\n  type = string\n}\n' >"${d}/modules/other/variables.tf"
  printf 'run "r" {}\n' >"${d}/modules/m/tests/plan.tftest.hcl"
  git -C "${d}" add -A
  git -C "${d}" commit -q -m "feat: add module m"
  git -C "${d}" checkout -q -b pr
  echo "${d}"
}

# commit <repo> <message>: commit every change in the work tree.
commit() { git -C "$1" add -A && git -C "$1" commit -q -m "$2"; }

# run <repo> [base]: run the checker inside <repo>; output in ${workdir}/out.
run() {
  (cd "$1" && bash "${SCRIPT}" "${2:-main}") >"${workdir}/out" 2>&1
}

# 1. Removing an input without a breaking marker fails and names it.
r="$(fixture remove-input)"
printf 'variable "b" {\n  type = string\n}\n' >"${r}/modules/m/variables.tf"
commit "${r}" "feat: drop a"
if run "${r}"; then bad "removed input without a marker fails"; else ok "removed input without a marker fails"; fi
grep -q 'modules/m: removed variable a' "${workdir}/out" && ok "names the removed input" || bad "names the removed input"
grep -q 'removed variable b' "${workdir}/out" && bad "does not name a kept input" || ok "does not name a kept input"

# 2. The same change marked `!` passes.
git -C "${r}" commit -q --amend -m "feat!: drop a"
if run "${r}"; then ok "feat!: marks the removal as breaking"; else bad "feat!: marks the removal as breaking"; fi
grep -q 'modules/m: removed variable a' "${workdir}/out" && ok "still lists the declared removal" || bad "still lists the declared removal"

# 3. A BREAKING CHANGE footer in any commit of the range also passes.
git -C "${r}" commit -q --amend -m "feat(m): drop a" -m "BREAKING CHANGE: input a is gone; use b."
if run "${r}"; then ok "BREAKING CHANGE footer marks the removal"; else bad "BREAKING CHANGE footer marks the removal"; fi

# 4. A scoped type with `!` passes; `!` elsewhere in the subject does not count.
git -C "${r}" commit -q --amend -m "refactor(m)!: drop a"
if run "${r}"; then ok "type(scope)!: marks the removal"; else bad "type(scope)!: marks the removal"; fi
git -C "${r}" commit -q --amend -m "feat: drop a!: really"
if run "${r}"; then bad "a ! later in the subject is not a marker"; else ok "a ! later in the subject is not a marker"; fi

# 5. Removing an output fails.
r="$(fixture remove-output)"
: >"${r}/modules/m/outputs.tf"
commit "${r}" "fix: drop x"
if run "${r}"; then bad "removed output without a marker fails"; else ok "removed output without a marker fails"; fi
grep -q 'modules/m: removed output x' "${workdir}/out" && ok "names the removed output" || bad "names the removed output"

# 6. Renaming an input is a removal.
r="$(fixture rename-input)"
printf 'variable "a_new" {\n  type = string\n}\n\nvariable "b" {\n  type = string\n}\n' >"${r}/modules/m/variables.tf"
commit "${r}" "feat: rename a"
if run "${r}"; then bad "renamed input fails"; else ok "renamed input fails"; fi
grep -q 'modules/m: removed variable a$' "${workdir}/out" && ok "rename names the old input" || bad "rename names the old input"

# 7. Adding inputs and outputs passes.
r="$(fixture add)"
printf '\nvariable "c" {\n  type    = string\n  default = null\n}\n' >>"${r}/modules/m/variables.tf"
printf '\noutput "y" {\n  value = var.b\n}\n' >>"${r}/modules/m/outputs.tf"
commit "${r}" "feat: add c and y"
if run "${r}"; then ok "added input and output pass"; else bad "added input and output pass"; fi

# 8. Moving a declaration to another file of the same module is not a removal.
r="$(fixture move)"
printf 'variable "b" {\n  type = string\n}\n' >"${r}/modules/m/variables.tf"
printf 'variable "a" {\n  type = string\n}\n' >"${r}/modules/m/inputs-extra.tf"
commit "${r}" "refactor: move a"
if run "${r}"; then ok "moving a variable between files passes"; else bad "moving a variable between files passes"; fi

# 9. Deleting a whole module removes its inputs.
r="$(fixture delete-module)"
git -C "${r}" rm -q -r modules/other
commit "${r}" "chore: delete other"
if run "${r}"; then bad "deleting a module fails"; else ok "deleting a module fails"; fi
grep -q 'modules/other: removed variable o' "${workdir}/out" && ok "names the deleted module" || bad "names the deleted module"

# 10. Test files are not module API.
r="$(fixture tests-only)"
: >"${r}/modules/m/tests/plan.tftest.hcl"
commit "${r}" "test: empty"
if run "${r}"; then ok "test-only changes pass"; else bad "test-only changes pass"; fi

# 10b. A module's examples/ and tests/ directories are not module API.
r="$(fixture examples)"
mkdir -p "${r}/modules/m/examples/basic" "${r}/modules/m/tests/setup"
printf 'variable "e" {\n  type = string\n}\n' >"${r}/modules/m/examples/basic/variables.tf"
printf 'variable "s" {\n  type = string\n}\n' >"${r}/modules/m/tests/setup/main.tf"
commit "${r}" "docs: add example and test helper"
git -C "${r}" branch -q -f main HEAD
rm "${r}/modules/m/examples/basic/variables.tf" "${r}/modules/m/tests/setup/main.tf"
commit "${r}" "docs: drop example and test helper inputs"
if run "${r}"; then ok "example and test helper inputs are not module API"; else bad "example and test helper inputs are not module API"; fi

# 11. Commits already on the base are outside the range: a breaking marker on
# main does not excuse a removal on the branch.
r="$(fixture base-marker)"
git -C "${r}" checkout -q main
printf '# note\n' >"${r}/README.md"
commit "${r}" "feat!: unrelated breaking change on main"
git -C "${r}" checkout -q pr
git -C "${r}" merge -q --no-edit main
printf 'variable "b" {\n  type = string\n}\n' >"${r}/modules/m/variables.tf"
commit "${r}" "feat: drop a"
if run "${r}"; then bad "a marker on the base branch does not count"; else ok "a marker on the base branch does not count"; fi

# 12. Usage errors.
if (cd "${r}" && bash "${SCRIPT}") >/dev/null 2>&1; then bad "a missing base ref fails"; else ok "a missing base ref fails"; fi
if run "${r}" no-such-ref; then bad "an unknown base ref fails"; else ok "an unknown base ref fails"; fi

printf 'test-check-module-api: %s failed\n' "${failures}"
[[ "${failures}" -eq 0 ]]
