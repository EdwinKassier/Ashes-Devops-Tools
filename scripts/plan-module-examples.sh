#!/usr/bin/env bash
# Plan every per-module example under mock providers.
#
# `terraform validate` accepts an example that cannot plan: a for_each over an
# unknown value, a module precondition, a variable validation that only sees
# the real input, a provider alias the module needs but the example does not
# pass. This gate copies each example to a hidden sibling directory
# (<module>/examples/.plan-check-<pid>, so `../..` sources stay inside the
# module package), writes a mock.tftest.hcl with a mock_provider for every
# provider and configuration alias the example declares plus realistic
# mock_data defaults, and runs `terraform init -backend=false` and
# `terraform test` (one `command = plan` run). No credentials, no apply.
#
# Tag-pinned examples (source = "git::...//modules/<path>?ref=vX.Y.Z", bumped
# by release-please) are rewritten to the local module path, so the plan checks
# the code in this checkout, not the published tag.
#
# Required example variables (secrets passed with TF_VAR_*) get a mock value:
# by name from known_value() below, else by type.
#
# `terraform test` fails a run on a failed `check` block assertion (a plain
# plan only warns), so an example must set the inputs that keep its checks
# quiet. Mocked computed attributes are unknown-free but synthetic, so a plan
# here does not prove the provider API accepts the values.
#
#   scripts/plan-module-examples.sh [DIR...]          (default: every modules/**/examples/basic)
#   scripts/plan-module-examples.sh --generate DIR    (print the generated mock.tftest.hcl, run nothing)
#   make examples-plan [EXAMPLES="dir ..."]
#
# Env: TERRAFORM (default terraform); TF_PLUGIN_CACHE_DIR is honoured by terraform.
# Exit: 0 every example plans, 1 any example failed, 2 usage error.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"
TERRAFORM="${TERRAFORM:-terraform}"

usage() {
  sed -n '/^#   scripts/p' "$0" | sed 's/^# *//' >&2
  exit 2
}

# One line per provider configuration the example declares: "<name>" for the
# default configuration (every required_providers entry and every provider
# block without alias) and "<name> <alias>" for each aliased provider block.
# Expects `terraform fmt` layout (one block opener per line).
provider_configs() {
  awk '
    function strip(s) { gsub(/"([^"\\]|\\.)*"/, "\"\"", s); sub(/#.*/, "", s); sub(/\/\/.*/, "", s); return s }
    function delta(s,  o, c) { o = gsub(/\{/, "{", s); c = gsub(/\}/, "}", s); return o - c }
    {
      line = $0
      s = strip(line)
      if (depth == 0 && match(line, /^provider[[:space:]]+"[^"]+"/)) {
        name = substr(line, RSTART, RLENGTH); sub(/^provider[[:space:]]+"/, "", name); sub(/"$/, "", name)
        inprov = 1; alias = ""
      }
      if (inprov && depth == 1 && match(line, /^[[:space:]]*alias[[:space:]]*=[[:space:]]*"[^"]+"/)) {
        alias = substr(line, RSTART, RLENGTH); sub(/^[^"]*"/, "", alias); sub(/"$/, "", alias)
      }
      if (rp && rpdepth == depth && match(line, /^[[:space:]]*[A-Za-z0-9_-]+[[:space:]]*=[[:space:]]*\{/)) {
        n = line; sub(/^[[:space:]]*/, "", n); sub(/[[:space:]]*=.*/, "", n); print n
      }
      if (!rp && match(s, /^[[:space:]]*required_providers[[:space:]]*\{/)) { rp = 1; rpdepth = depth + 1 }
      depth += delta(s)
      if (rp && depth < rpdepth) rp = 0
      if (inprov && depth == 0) { print (alias == "" ? name : name " " alias); inprov = 0 }
    }
  ' "$@" | sort -u
}

# One line per variable without a default: "<name> <type expression>".
required_variables() {
  awk '
    function strip(s) { gsub(/"([^"\\]|\\.)*"/, "\"\"", s); sub(/#.*/, "", s); return s }
    function delta(s,  o, c) { o = gsub(/[\{\(\[]/, "{", s); c = gsub(/[\}\)\]]/, "}", s); return o - c }
    {
      line = $0
      if (depth == 0 && match(line, /^variable[[:space:]]+"[^"]+"/)) {
        name = substr(line, RSTART, RLENGTH); sub(/^variable[[:space:]]+"/, "", name); sub(/"$/, "", name)
        invar = 1; hasdef = 0; type = "string"
      }
      if (invar && depth == 1 && line ~ /^[[:space:]]*default[[:space:]]*=/) hasdef = 1
      if (invar && depth == 1 && line ~ /^[[:space:]]*type[[:space:]]*=/) { type = line; sub(/^[[:space:]]*type[[:space:]]*=[[:space:]]*/, "", type) }
      depth += delta(strip(line))
      if (invar && depth == 0) { if (!hasdef) print name, type; invar = 0 }
    }
  ' "$@"
}

# Mock values for required example inputs that a module validates by format.
known_value() {
  case "$1" in
    postgres_url) echo '"postgresql://postgres.abcdefghijklmnopqrst:mock@aws-0-eu-west-2.pooler.supabase.com:5432/postgres"' ;;
    supabase_ssl_cert) echo '"bW9jay1jZXJ0"' ;;
    slack_webhook_url) echo '"https://hooks.slack.com/services/T00000000/B00000000/mock-placeholder"' ;;
    *_email) echo '"mock-group@corp.test"' ;;
    vault_secrets) echo '{ XERO_CLIENT_ID = "mock-id" }' ;;
    *) return 1 ;;
  esac
}

type_value() {
  local name="$1" type="$2"
  case "${type}" in
    list* | set* | tuple*) echo '[]' ;;
    map* | object*) echo '{}' ;;
    number*) echo '1' ;;
    bool*) echo 'true' ;;
    *) printf '"mock-%s-0123456789abcdef"\n' "${name//_/-}" ;;
  esac
}

AWS_MOCKS='  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_region" {
    defaults = { name = "eu-west-2", region = "eu-west-2" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111", arn = "arn:aws:iam::111111111111:role/tfc-apply" }
  }
  mock_data "aws_ssoadmin_instances" {
    defaults = { arns = ["arn:aws:sso:::instance/ssoins-1234567890abcdef"], identity_store_ids = ["d-1234567890"] }
  }
  mock_data "aws_availability_zones" {
    defaults = { names = ["eu-west-2a", "eu-west-2b", "eu-west-2c"], zone_ids = ["euw2-az1", "euw2-az2", "euw2-az3"] }
  }
  mock_data "aws_organizations_organization" {
    defaults = {
      id                = "o-abcdef1234"
      master_account_id = "111111111111"
      roots             = [{ id = "r-ab12", arn = "arn:aws:organizations::111111111111:root/o-abcdef1234/r-ab12", name = "Root", policy_types = [] }]
    }
  }'

GOOGLE_MOCKS='  mock_data "google_compute_zones" {
    defaults = { names = ["europe-west2-a", "europe-west2-b", "europe-west2-c"] }
  }
  mock_data "google_project" {
    defaults = { number = "123456789012", project_id = "my-project" }
  }
  mock_data "google_organization" {
    defaults = { org_id = "123456789012", name = "organizations/123456789012", directory_customer_id = "C0abc1234" }
  }
  mock_data "google_billing_account" {
    defaults = { id = "ABCDEF-123456-789012", name = "billingAccounts/ABCDEF-123456-789012", open = true }
  }
  mock_resource "google_folder" {
    defaults = { folder_id = "123456789001", name = "folders/123456789001" }
  }
  mock_resource "google_project" {
    defaults = { number = "123456789012" }
  }'

# Print the mock.tftest.hcl for the example in $1.
generate_test() {
  local dir="$1" name alias type value tf=()
  shopt -s nullglob
  tf=("${dir}"/*.tf)
  shopt -u nullglob
  [ "${#tf[@]}" -gt 0 ] || { echo "no .tf files in ${dir}" >&2; return 1; }
  echo "# Generated by scripts/plan-module-examples.sh. Do not commit."
  while read -r name alias; do
    [ -n "${name}" ] || continue
    echo
    echo "mock_provider \"${name}\" {"
    [ -z "${alias}" ] || echo "  alias = \"${alias}\""
    case "${name}" in
      aws) echo "${AWS_MOCKS}" ;;
      google | google-beta) echo "${GOOGLE_MOCKS}" ;;
    esac
    echo "}"
  done < <(provider_configs "${tf[@]}")
  local vars
  vars="$(required_variables "${tf[@]}")"
  if [ -n "${vars}" ]; then
    echo
    echo "variables {"
    while read -r name type; do
      value="$(known_value "${name}")" || value="$(type_value "${name}" "${type}")"
      echo "  ${name} = ${value}"
    done <<<"${vars}"
    echo "}"
  fi
  echo
  echo 'run "plan" {'
  echo '  command = plan'
  echo '}'
}

work=""
cleanup() { [ -z "${work}" ] || rm -rf "${work}"; }
trap cleanup EXIT
trap 'exit 130' INT TERM

# Plan one example; print its log on failure. Returns non-zero on failure.
plan_one() {
  local dir="${1%/}" module up f log rc=0
  dir="${dir#"${REPO_ROOT}"/}"
  if [ ! -f "${dir}/versions.tf" ]; then
    echo "  no versions.tf in ${dir}" >&2
    return 1
  fi
  module="$(dirname "$(dirname "${dir}")")"
  work="${module}/examples/.plan-check-$$"
  rm -rf "${work}"
  mkdir -p "${work}"
  cp "${dir}"/*.tf "${work}/"
  [ ! -f "${dir}/.terraform.lock.hcl" ] || cp "${dir}/.terraform.lock.hcl" "${work}/"
  # ../ once per path component of the work dir: from there to the repo root.
  up="$(awk -F/ '{ for (i = 1; i <= NF; i++) printf "../" }' <<<"${work}")"
  for f in "${work}"/*.tf; do
    if grep -qE '^[[:space:]]*source[[:space:]]*=[[:space:]]*"git::' "${f}"; then
      sed -E 's#^([[:space:]]*source[[:space:]]*=[[:space:]]*)"git::[^"]*//(modules/[^"?]*)(\?[^"]*)?"#\1"'"${up}"'\2"#' "${f}" >"${f}.new"
      mv "${f}.new" "${f}"
      if grep -qE '^[[:space:]]*source[[:space:]]*=[[:space:]]*"git::' "${f}"; then
        echo "  cannot map a git:: source in ${dir}/$(basename "${f}") to a repo path (expected git::...//modules/<path>?ref=...)" >&2
        rm -rf "${work}"
        work=""
        return 1
      fi
    fi
  done
  generate_test "${work}" >"${work}/mock.tftest.hcl"
  log="${work}/.plan.log"
  local attempt ok=0
  for attempt in 1 2 3; do
    if "${TERRAFORM}" -chdir="${work}" init -backend=false -input=false -no-color >"${log}" 2>&1; then
      ok=1
      break
    fi
    [ "${attempt}" -eq 3 ] || sleep $((attempt * 5))
  done
  if [ "${ok}" -ne 1 ]; then
    rc=1
  elif ! "${TERRAFORM}" -chdir="${work}" test -no-color >>"${log}" 2>&1; then
    rc=1
  fi
  if [ "${rc}" -ne 0 ]; then
    sed 's/^/    /' "${log}" | tail -n 60 >&2
  fi
  rm -rf "${work}"
  work=""
  return "${rc}"
}

if [ "${1:-}" = "--generate" ]; then
  [ "$#" -eq 2 ] || usage
  generate_test "${2%/}"
  exit 0
fi
case "${1:-}" in -h | --help) usage ;; -*) echo "unknown option: $1" >&2; usage ;; esac

dirs=("$@")
if [ "${#dirs[@]}" -eq 0 ]; then
  while IFS= read -r d; do dirs+=("$d"); done < <(./scripts/terraform-roots.sh module-examples)
  if [ "${#dirs[@]}" -eq 0 ]; then
    echo "plan-module-examples: no modules/**/examples/basic found" >&2
    exit 1
  fi
fi

passed=0
failed=()
start=${SECONDS}
for dir in "${dirs[@]}"; do
  if plan_one "${dir}"; then
    echo "PASS ${dir}"
    passed=$((passed + 1))
  else
    echo "FAIL ${dir}"
    failed+=("${dir}")
  fi
done
echo "plan-module-examples: ${passed} passed, ${#failed[@]} failed ($((SECONDS - start))s)"
if [ "${#failed[@]}" -gt 0 ]; then
  printf '  failed: %s\n' "${failed[@]}" >&2
  exit 1
fi
