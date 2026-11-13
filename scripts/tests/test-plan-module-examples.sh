#!/usr/bin/env bash
# scripts/plan-module-examples.sh: the generated mock test declares every
# provider configuration and alias, required inputs get mock values, an example
# that plans passes, an example that breaks a module's variable validation
# fails, and the temporary copy is always removed.
#   bash scripts/tests/test-plan-module-examples.sh   (make test-scripts)
#
# Offline. The generator cases need nothing; the plan cases need terraform
# (skipped when it is not on PATH) and use only the built-in terraform_data;
# the alias plan case also needs hashicorp/aws in TF_PLUGIN_CACHE_DIR and is
# installed from there as a filesystem mirror (skipped when it is not cached).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/plan-module-examples.sh"
TERRAFORM="${TERRAFORM:-terraform}"
failures=0
ok() { printf '  ok   %s\n' "$1"; }
bad() {
  failures=$((failures + 1))
  printf '  FAIL %s\n' "$1" >&2
}
skip() { printf '  skip %s\n' "$1"; }

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

# A module with a validated input and a terraform_data resource.
mod="${tmp}/modules/demo/thing"
mkdir -p "${mod}/examples/basic"
cat >"${mod}/main.tf" <<'EOF'
variable "name" {
  type = string
  validation {
    condition     = can(regex("^[a-z]+$", var.name))
    error_message = "name must be lower-case letters."
  }
}

resource "terraform_data" "this" {
  input = var.name
}
EOF
cat >"${mod}/examples/basic/versions.tf" <<'EOF'
terraform {
  required_version = ">= 1.17"
}
EOF
cat >"${mod}/examples/basic/main.tf" <<'EOF'
module "thing" {
  source = "../.."
  name   = "demo"
}
EOF

# An example with aliases and a required input (generator only).
gen="${tmp}/gen"
mkdir -p "${gen}"
cat >"${gen}/versions.tf" <<'EOF'
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.46.0, < 7.0.0"
    }
    google = {
      source = "hashicorp/google"
    }
  }
}
EOF
cat >"${gen}/main.tf" <<'EOF'
provider "aws" {
  region = "eu-west-2"
}

provider "aws" {
  alias  = "management" # the org management account
  region = "eu-west-2"
  assume_role {
    role_arn = "arn:aws:iam::111111111111:role/x"
  }
}

provider "google" {
  alias = "billing"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "owner_email" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "subnets" {
  type = list(object({
    cidr = string
  }))
}
EOF
out="$(bash "${SCRIPT}" --generate "${gen}")"
for want in 'mock_provider "aws" {' 'alias = "management"' 'alias = "billing"' 'mock_data "aws_caller_identity"' \
  'mock_data "google_compute_zones"' 'owner_email = "mock-group@corp.test"' 'subnets = []' 'command = plan'; do
  grep -qF -- "${want}" <<<"${out}" && ok "generated test has: ${want}" || bad "generated test lacks: ${want}"
done
[ "$(grep -c '^mock_provider "aws"' <<<"${out}")" -eq 2 ] && ok "one aws mock per configuration (default + alias)" || bad "aws mocks: $(grep -c '^mock_provider "aws"' <<<"${out}")"
[ "$(grep -c '^mock_provider "google"' <<<"${out}")" -eq 2 ] && ok "google: required_providers default + alias" || bad "google mocks: $(grep -c '^mock_provider "google"' <<<"${out}")"
grep -qE '^  db_password = "mock-db-password-' <<<"${out}" && ok "required string input gets a mock value" || bad "db_password has no mock value"
grep -q 'tags =' <<<"${out}" && bad "an input with a default must not be set" || ok "an input with a default is left alone"

if bash "${SCRIPT}" --bogus >/dev/null 2>&1; then rc=0; else rc=$?; fi
[ "${rc}" -eq 2 ] && ok "unknown option exits 2" || bad "unknown option exits ${rc}"

if ! command -v "${TERRAFORM}" >/dev/null 2>&1; then
  skip "plan cases: ${TERRAFORM} is not on PATH"
else
  # Pass: the example plans.
  if bash "${SCRIPT}" "${mod}/examples/basic" >"${tmp}/pass.log" 2>&1; then
    ok "an example that plans passes"
  else
    bad "an example that plans failed: $(tail -20 "${tmp}/pass.log")"
  fi
  grep -q "^PASS ${mod}/examples/basic$" "${tmp}/pass.log" && ok "PASS line printed" || bad "no PASS line"

  # Fail: the example breaks the module's variable validation.
  sed -i.bak 's/name   = "demo"/name   = "Not-Valid"/' "${mod}/examples/basic/main.tf"
  rm -f "${mod}/examples/basic/main.tf.bak"
  if bash "${SCRIPT}" "${mod}/examples/basic" >"${tmp}/fail.log" 2>&1; then rc=0; else rc=$?; fi
  [ "${rc}" -eq 1 ] && ok "an example that breaks a validation exits 1" || bad "validation break exits ${rc}"
  grep -q "^FAIL ${mod}/examples/basic$" "${tmp}/fail.log" && ok "FAIL line printed" || bad "no FAIL line"
  grep -q "name must be lower-case letters" "${tmp}/fail.log" && ok "the plan error is shown" || bad "plan error not shown"
  [ -z "$(find "${mod}/examples" -name '.plan-check-*')" ] && ok "temporary copy removed" || bad "temporary copy left behind"

  # Alias: the example passes an aliased aws provider to the module. Unmocked,
  # that configuration would need AWS credentials, and the module checks the
  # account_id is 12 digits, so a pass shows the alias got the aws mock_data.
  cache="${TF_PLUGIN_CACHE_DIR:-}"
  if [ -z "${cache}" ] || [ ! -d "${cache}/registry.terraform.io/hashicorp/aws" ]; then
    skip "alias plan case: hashicorp/aws is not in TF_PLUGIN_CACHE_DIR"
  else
    am="${tmp}/modules/demo/aliased"
    mkdir -p "${am}/examples/basic"
    cat >"${am}/main.tf" <<'EOF'
terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.other]
    }
  }
}

data "aws_caller_identity" "other" {
  provider = aws.other
}

resource "terraform_data" "account" {
  input = data.aws_caller_identity.other.account_id
  lifecycle {
    precondition {
      condition     = can(regex("^[0-9]{12}$", data.aws_caller_identity.other.account_id))
      error_message = "account_id must be 12 digits."
    }
  }
}
EOF
    cat >"${am}/examples/basic/versions.tf" <<'EOF'
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}
EOF
    cat >"${am}/examples/basic/main.tf" <<'EOF'
provider "aws" {
  alias  = "second"
  region = "eu-west-2"
}

module "aliased" {
  source    = "../.."
  providers = { aws.other = aws.second }
}
EOF
    cat >"${tmp}/cli.tfrc" <<EOF
provider_installation {
  filesystem_mirror {
    path    = "${cache}"
    include = ["registry.terraform.io/hashicorp/aws"]
  }
  direct {
    exclude = ["registry.terraform.io/hashicorp/aws"]
  }
}
EOF
    if env -u AWS_PROFILE -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY AWS_EC2_METADATA_DISABLED=true \
      TF_CLI_CONFIG_FILE="${tmp}/cli.tfrc" TF_PLUGIN_CACHE_DIR="" \
      bash "${SCRIPT}" "${am}/examples/basic" >"${tmp}/alias.log" 2>&1; then
      ok "an example with an aliased provider plans (the alias is mocked)"
    else
      bad "aliased example failed: $(tail -20 "${tmp}/alias.log")"
    fi
  fi
fi

printf 'test-plan-module-examples: %s failed\n' "${failures}"
[[ "${failures}" -eq 0 ]]
