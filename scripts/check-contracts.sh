#!/usr/bin/env bash
# Cross-root contract guard. Every producer root publishes ONE non-sensitive
# `contract` output; every consumer reads only `.outputs.contract` (or, for
# tfe_outputs, `.nonsensitive_values.contract`).
#
# Fails when:
#   1. a producer root lacks `output "contract"`, or marks it sensitive (one
#      sensitive attribute would move the whole object into tfe_outputs'
#      sensitive_values, out of tfc-admin's reach);
#   2. a consumer (envs/**, templates/**) reads terraform_remote_state outputs
#      or tfe_outputs values other than `contract`. The one tolerated bare read
#      is the pre-contract fallback written on one line:
#        try(<ref>.outputs.contract, <ref>.outputs)
#      (removed at v1.0 with the individual outputs, see UPGRADING.md);
#   3. two consumers of the same upstream declare a `<x>_contract` variable
#      with different types (compared per cloud: envs/<cloud>/** and
#      templates/<cloud>/**).
#
# Allowlisted data sources (CONTRACT_ALLOWLIST, space-separated names): the SaaS
# secret bridge (`saas`, reads supabase_* / bridge_version) and the envs/saas
# user-defined cross-cloud seam (`cross_cloud`, reads outputs[<key>]).
#
#   scripts/check-contracts.sh [REPO_ROOT]
set -euo pipefail

REPO_ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PRODUCERS="${CONTRACT_PRODUCERS:-envs/aws/organization envs/aws/security envs/aws/network envs/gcp/bootstrap envs/gcp/organization envs/gcp/projects envs/gcp/network-hub}"
ALLOWLIST="${CONTRACT_ALLOWLIST:-saas cross_cloud}"

errors=0
fail() {
  errors=$((errors + 1))
  printf 'check-contracts: %s\n' "$1" >&2
}

# ── 1. producers ──────────────────────────────────────────────────────────────
for p in ${PRODUCERS}; do
  dir="${REPO_ROOT}/${p}"
  if [[ ! -d "${dir}" ]]; then
    fail "${p}: producer root not found"
    continue
  fi
  block="$(awk '/^output "contract"[[:space:]]*\{/{on=1} on{print} on&&/^\}/{exit}' "${dir}"/*.tf 2>/dev/null || true)"
  if [[ -z "${block}" ]]; then
    fail "${p}: producer has no output \"contract\""
  elif grep -Eq '^[[:space:]]*sensitive[[:space:]]*=[[:space:]]*true' <<<"${block}"; then
    fail "${p}: output \"contract\" is sensitive; it must stay non-sensitive (tfe_outputs nonsensitive_values)"
  fi
done

# ── 2. consumer reads ─────────────────────────────────────────────────────────
allowed() {
  local n
  for n in ${ALLOWLIST}; do
    [[ "$1" == "${n}" ]] && return 0
  done
  return 1
}

ref_re='(terraform_remote_state|tfe_outputs)\.[A-Za-z0-9_]+(\[[^]]*\])?\.(outputs|nonsensitive_values|values)'

# Only lines that mention a remote-state / tfe_outputs read are inspected.
while IFS= read -r match; do
  [[ -z "${match}" ]] && continue
  f="${match%%:*}"
  rest="${match#*:}"
  lineno="${rest%%:*}"
  line="${rest#*:}"
  rel="${f#"${REPO_ROOT}"/}"
  {
    # Drop comments (whole-line and trailing # / //); strings with # are rare
    # in these reads and would only cause a false pass, never a false fail.
    code="${line%%#*}"
    code="${code%%//*}"
    grep -Eq "${ref_re}" <<<"${code}" || continue
    # Accepted forms: <ref>.contract, and the one-line legacy fallback.
    code="$(sed -E \
      -e "s/${ref_re}\.contract([^A-Za-z0-9_]|$)/CONTRACT_OK\4/g" \
      -e 's/CONTRACT_OK, [A-Za-z0-9_.]*(\[[^]]*\])?\.(outputs|nonsensitive_values)([^A-Za-z0-9_.[]|$)/CONTRACT_OK, LEGACY_OK\3/g' \
      <<<"${code}")"
    while IFS= read -r hit; do
      [[ -z "${hit}" ]] && continue
      name="$(sed -E 's/^(terraform_remote_state|tfe_outputs)\.([A-Za-z0-9_]+).*/\2/' <<<"${hit}")"
      allowed "${name}" && continue
      fail "${rel}:${lineno}: reads '${hit}' — consumers read only .outputs.contract (.nonsensitive_values.contract)"
    done < <(grep -oE "${ref_re}(\.[A-Za-z0-9_]+|\[)?" <<<"${code}" || true)
  }
done < <(find "${REPO_ROOT}/envs" "${REPO_ROOT}/templates" -name '*.tf' -not -path '*/.terraform/*' -print0 2>/dev/null |
  xargs -0 grep -nHE "${ref_re}" 2>/dev/null || true)

# ── 3. identical contract variable types per upstream ─────────────────────────
types_file="$(mktemp)"
trap 'rm -f "${types_file}"' EXIT
while IFS= read -r -d '' f; do
  rel="${f#"${REPO_ROOT}"/}"
  cloud="$(awk -F/ '{print $2}' <<<"${rel}")"
  # templates/shared is a cloud-agnostic skeleton, not a consumer.
  [[ "${rel}" == templates/shared/* ]] && continue
  # Emit "<cloud>/<var>\t<normalised type>\t<file>" per *_contract variable: the
  # type expression runs from `type =` until the line before `default`.
  awk -v cloud="${cloud}" -v file="${rel}" '
    /^variable "[a-z0-9_]+_contract"[[:space:]]*\{/ {
      name = $2; gsub(/"/, "", name); invar = 1; intype = 0; t = ""; next
    }
    invar && /^\}/ { if (t != "") printf "%s/%s\t%s\t%s\n", cloud, name, t, file; invar = 0; intype = 0; next }
    invar && /^  type[[:space:]]*=/ { intype = 1 }
    invar && intype && /^  (default|validation|nullable|sensitive|description)[[:space:]=]/ { intype = 0 }
    invar && intype { line = $0; gsub(/[[:space:]]+/, "", line); t = t line }
  ' "${f}" >>"${types_file}"
done < <(find "${REPO_ROOT}/envs" "${REPO_ROOT}/templates" -name 'variables.tf' -not -path '*/.terraform/*' -print0 2>/dev/null)

while IFS= read -r key; do
  n_types="$(awk -F'\t' -v k="${key}" '$1 == k {print $2}' "${types_file}" | sort -u | wc -l | tr -d ' ')"
  if [[ "${n_types}" -gt 1 ]]; then
    files="$(awk -F'\t' -v k="${key}" '$1 == k {print $3}' "${types_file}" | tr '\n' ' ')"
    fail "${key}: contract variable type differs across consumers: ${files}"
  fi
done < <(cut -f1 "${types_file}" | sort -u)

if [[ "${errors}" -gt 0 ]]; then
  printf 'check-contracts: %s problem(s)\n' "${errors}" >&2
  exit 1
fi
echo "check-contracts: OK"
