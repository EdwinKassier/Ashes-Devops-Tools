#!/usr/bin/env bash
# The terraform_validate pre-commit hook validates only the directories
# `make validate-all` validates: it skips a module that declares
# configuration_aliases, validates an ordinary module, and ignores a path that
# is not a validate target. terraform is a stub that records its calls, so the
# test needs no providers or network.
#   bash scripts/tests/test-precommit-terraform-validate.sh   (make test-scripts)
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPO_ROOT}"
failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() {
  failures=$((failures + 1))
  printf '  FAIL %s\n' "$1" >&2
}

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
mkdir -p "${tmp}/bin"
cat >"${tmp}/bin/terraform" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${TF_STUB_LOG}"
STUB
chmod +x "${tmp}/bin/terraform"
export TF_STUB_LOG="${tmp}/calls.log"

hook() {
  : >"${TF_STUB_LOG}"
  PATH="${tmp}/bin:${PATH}" scripts/precommit-terraform-validate.sh "$@" >"${tmp}/out.log" 2>&1
}

# A module that declares configuration_aliases: skipped, no terraform call.
alias_dir="modules/aws/stages/workload"
if grep -rqE 'configuration_aliases[[:space:]]*=' "${alias_dir}" --include='*.tf'; then
  ok "${alias_dir} declares configuration_aliases (fixture holds)"
else
  bad "${alias_dir} no longer declares configuration_aliases; pick another fixture"
fi
if hook "${alias_dir}/main.tf"; then rc=0; else rc=$?; fi
[[ "${rc}" -eq 0 ]] && ok "alias module exits 0" || bad "alias module exits ${rc}"
[[ ! -s "${TF_STUB_LOG}" ]] && ok "alias module makes no terraform call" || bad "alias module called terraform: $(cat "${TF_STUB_LOG}")"
grep -q "Skipping validate for ${alias_dir}" "${tmp}/out.log" && ok "alias module skip is reported" || bad "alias module skip is not reported"

# An ordinary module: init and validate run in that directory.
plain_dir="modules/aws/network/vpc"
if grep -rqE 'configuration_aliases[[:space:]]*=' "${plain_dir}" --include='*.tf'; then
  bad "${plain_dir} declares configuration_aliases; pick another fixture"
fi
if hook "${plain_dir}/main.tf" "${plain_dir}/variables.tf"; then rc=0; else rc=$?; fi
[[ "${rc}" -eq 0 ]] && ok "plain module exits 0" || bad "plain module exits ${rc}"
grep -qxF -- "-chdir=${plain_dir} init -backend=false -input=false" "${TF_STUB_LOG}" && ok "plain module is initialised" || bad "plain module is not initialised: $(cat "${TF_STUB_LOG}")"
grep -qxF -- "-chdir=${plain_dir} validate -no-color" "${TF_STUB_LOG}" && ok "plain module is validated" || bad "plain module is not validated: $(cat "${TF_STUB_LOG}")"
[[ "$(grep -c 'validate' "${TF_STUB_LOG}")" -eq 1 ]] && ok "two files in one module validate it once" || bad "module validated more than once"

# A failing validate makes the hook fail.
cat >"${tmp}/bin/terraform" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${TF_STUB_LOG}"
case "$*" in *validate*) exit 1 ;; esac
STUB
if hook "${plain_dir}/main.tf"; then rc=0; else rc=$?; fi
[[ "${rc}" -ne 0 ]] && ok "a validate error fails the hook" || bad "a validate error does not fail the hook"

# A path that is not a validate target: ignored, no terraform call.
if hook "scripts/not-a-target/x.tf"; then rc=0; else rc=$?; fi
[[ "${rc}" -eq 0 && ! -s "${TF_STUB_LOG}" ]] && ok "hook ignores a non-target path" || bad "hook handled a non-target path (rc=${rc})"

# An example directory: ignored even though make validate-all lists it.
examples="$(./scripts/terraform-roots.sh examples)"
example_dir="${examples%%$'\n'*}"
if [[ -n "${example_dir}" ]]; then
  if hook "${example_dir}/main.tf"; then rc=0; else rc=$?; fi
  [[ "${rc}" -eq 0 && ! -s "${TF_STUB_LOG}" ]] && ok "hook ignores an example (${example_dir})" || bad "hook ran terraform on an example"
fi

printf 'test-precommit-terraform-validate: %s failed\n' "${failures}"
[[ "${failures}" -eq 0 ]]
