#!/usr/bin/env bash
# Tests for scripts/check-example-module-attrs.py against temp example trees.
#   bash scripts/tests/test-check-example-module-attrs.sh   (make test-scripts)
# Needs python-hcl2 (.github/requirements/hcl2.txt).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-example-module-attrs.py"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }

# The kms module's keys type, as in modules/gcp/governance/kms/variables.tf.
KMS_VARS='variable "project_id" {
  type = string
}
variable "keys" {
  type = map(object({
    rotation_period      = optional(string, "7776000s") # 90 days
    labels               = optional(map(string), {})
    encrypter_decrypters = optional(list(string), [])
  }))
  default = {}
}
variable "perimeter" {
  type = optional(object({
    services = optional(list(string), ["storage.googleapis.com"])
    rules = optional(list(object({
      identities = list(string)
      sources    = optional(map(object({ level = string })), {})
    })), [])
  }))
  default = null
}
variable "anything" {
  type    = any
  default = null
}'

# case <name> <example main.tf>: a tree with examples/r/main.tf calling modules/m.
case_tree() {
  local t="${workdir}/$1"
  mkdir -p "${t}/modules/m" "${t}/examples/r" "${t}/examples/system-design"
  printf '%s\n' "${KMS_VARS}" >"${t}/modules/m/variables.tf"
  printf '%s\n' "$2" >"${t}/examples/r/main.tf"
  # system-design holds Markdown snippets: never scanned.
  printf 'module "x" {\n  source = "../../modules/missing"\n}\n' >"${t}/examples/system-design/main.tf"
  echo "${t}/examples"
}

# expect_rc <label> <rc> <examples dir> [<text the output must contain>]
expect_rc() {
  local rc=0
  python3 -I "${SCRIPT}" "$3" >"${workdir}/out" 2>&1 || rc=$?
  if [ "${rc}" -ne "$2" ]; then
    bad "$1 (rc=${rc}, want $2)"
    cat "${workdir}/out" >&2
  elif [ -n "${4:-}" ] && ! grep -qF -- "$4" "${workdir}/out"; then
    bad "$1 (output lacks: $4)"
    cat "${workdir}/out" >&2
  else
    ok "$1"
  fi
}

# The shape examples/kms/main.tf had at 21b9b4da: iam_bindings is not a keys
# attribute, so Terraform dropped it and no grant was made.
expect_rc "old kms example shape (iam_bindings in keys) fails" 1 "$(case_tree oldkms 'module "kms" {
  source     = "../../modules/m"
  project_id = "p"
  keys = {
    "app-data-key" = {
      rotation_period = "7776000s"
      iam_bindings = {
        "roles/cloudkms.cryptoKeyEncrypterDecrypter" = ["serviceAccount:a@p.iam.gserviceaccount.com"]
      }
    }
  }
}')" 'keys["app-data-key"].iam_bindings is not an attribute'
expect_rc "fixed kms example shape passes" 0 "$(case_tree newkms 'module "kms" {
  source     = "../../modules/m"
  project_id = "p"
  keys = {
    "app-data-key" = {
      rotation_period      = "7776000s"
      encrypter_decrypters = ["serviceAccount:a@p.iam.gserviceaccount.com"]
    }
    "log-encryption-key" = {}
  }
}')"
expect_rc "unknown top-level argument fails" 1 "$(case_tree toplevel 'module "kms" {
  source  = "../../modules/m"
  keyring = "x"
}')" "keyring is not a variable"
expect_rc "unknown key in optional(object) fails" 1 "$(case_tree optobj 'module "kms" {
  source = "../../modules/m"
  perimeter = {
    services = ["a"]
    dry_run  = true
  }
}')" "perimeter.dry_run"
expect_rc "unknown key two levels down in list(object) > map(object) fails" 1 "$(case_tree deep 'module "kms" {
  source = "../../modules/m"
  perimeter = {
    rules = [{
      identities = ["x"]
      sources    = { a = { level = "l", region = "r" } }
    }]
  }
}')" 'perimeter.rules[0].sources["a"].region'
expect_rc "expression values and any-typed inputs are not followed" 0 "$(case_tree expr 'locals {
  keys = { k = { bogus = 1 } }
}
module "kms" {
  source    = "../../modules/m"
  keys      = local.keys
  anything  = { whatever = 1 }
  for_each  = toset(["a"])
}')"
expect_rc "missing module source fails" 1 "$(case_tree nosrc 'module "kms" {
  source = "../../modules/nope"
}')" "does not exist"
expect_rc "unparseable example fails closed" 1 "$(case_tree broken 'module "kms" {')" "cannot parse"
expect_rc "the repository examples pass" 0 "${REPO_ROOT}/examples"

if [ "${failures}" -ne 0 ]; then
  echo "${failures} failure(s)" >&2
  exit 1
fi
echo "check-example-module-attrs: all cases pass"
