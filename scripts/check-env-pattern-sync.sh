#!/usr/bin/env bash
# Fail when the code-execution env var list differs between tfc-admin and the
# tfc_admin_guard policy. tfc-admin refuses those names at plan time
# (code_exec_env_pattern); the guard flags a tfe_variable that writes one
# (the part of steering_env_pattern after the TFC_/TF_CLI_ARGS/TFE_/TF_TOKEN_
# prefixes). Both must name the same set.
#
#   scripts/check-env-pattern-sync.sh [MAIN_TF] [GUARD_REGO]   (CI via check-consistency.sh)
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tf="${1:-${REPO_ROOT}/envs/tfc-admin/main.tf}"
rego="${2:-${REPO_ROOT}/policies/opa-destructive/tfc_admin_guard.rego}"

# code_exec_env_pattern = "^(<list>)$"
tf_list=$(sed -n 's/^[[:space:]]*code_exec_env_pattern[[:space:]]*=[[:space:]]*"\^(\(.*\))\$"[[:space:]]*$/\1/p' "${tf}")
# steering_env_pattern := `^((TFC_|TF_CLI_ARGS|TFE_|TF_TOKEN_).*|<list>)$`
# shellcheck disable=SC2016 # the backticks are literal Rego raw-string quotes.
rego_list=$(sed -n 's/^steering_env_pattern[[:space:]]*:=[[:space:]]*`\^((TFC_|TF_CLI_ARGS|TFE_|TF_TOKEN_)\.\*|\(.*\))\$`[[:space:]]*$/\1/p' "${rego}")

if [[ -z "${tf_list}" || $(printf '%s\n' "${tf_list}" | wc -l) -ne 1 ]]; then
  echo "check-env-pattern-sync: cannot read one code_exec_env_pattern = \"^(...)\$\" from ${tf}" >&2
  exit 2
fi
if [[ -z "${rego_list}" || $(printf '%s\n' "${rego_list}" | wc -l) -ne 1 ]]; then
  echo "check-env-pattern-sync: cannot read one steering_env_pattern := \`^((TFC_|TF_CLI_ARGS|TFE_|TF_TOKEN_).*|...)\$\` from ${rego}" >&2
  exit 2
fi
if [[ "${tf_list}" != "${rego_list}" ]]; then
  echo "check-env-pattern-sync: the code-execution env var lists differ" >&2
  echo "  ${tf} code_exec_env_pattern: ${tf_list}" >&2
  echo "  ${rego} steering_env_pattern tail: ${rego_list}" >&2
  echo "  Change both to the same list." >&2
  exit 1
fi
echo "check-env-pattern-sync: OK"
