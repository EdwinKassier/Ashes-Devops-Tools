# Allowlists for no_plan_time_code_execution (same package). A fork that adds
# a provider, needs another remote-state backend or another endpoint switch
# edits ONLY this file, in a reviewed change; the rules stay in
# no_plan_time_code_execution.rego. HCP Terraform loads every .rego file in
# policies/opa, so this file needs no entry in policies.hcl.
package terraform.policies.no_plan_time_code_execution

import rego.v1

# Every provider that a root, module or template of this repo declares, plus
# the built-in provider of terraform_data / terraform_remote_state. azurerm is
# listed for the commented example in templates/shared/cloud-root.
allowed_provider_sources := {
	"registry.terraform.io/hashicorp/archive",
	"registry.terraform.io/hashicorp/aws",
	"registry.terraform.io/hashicorp/azurerm",
	"registry.terraform.io/hashicorp/google",
	"registry.terraform.io/hashicorp/google-beta",
	"registry.terraform.io/hashicorp/null",
	"registry.terraform.io/hashicorp/random",
	"registry.terraform.io/hashicorp/tfe",
	"registry.terraform.io/supabase/supabase",
	"registry.terraform.io/vercel/vercel",
	"terraform.io/builtin/terraform",
}

# Provider arguments that match endpoint_key_pattern but take no host name:
# switches and enums that pick another AWS-owned endpoint.
endpoint_key_exceptions := {
	"use_fips_endpoint",
	"use_dualstack_endpoint",
	"s3_us_east_1_regional_endpoint",
}

# Backends a data "terraform_remote_state" may read. Every remote-state read
# in this repo uses "cloud" (HCP Terraform); "remote" is its older name.
allowed_remote_state_backends := {"cloud", "remote"}

# Action block types (Terraform 1.14+) that a configuration may declare. This
# repo declares none, so every action block is denied.
allowed_action_types := set()

# Credential arguments (credential_key_pattern) that a provider of this repo
# sets, as "<provider type>/<argument>=<reference>". The argument is allowed
# when every reference of its expression is one of these or a path below it.
#   aws shared_config_files: the TFC dynamic-credentials file of
#     envs/aws/security and envs/aws/backup (multi-account roots).
#   google / google-beta impersonate_service_account: every GCP root (null in
#     HCP Terraform; set for deliberate local runs).
#   tfe token: the SaaS bridge placeholder in envs/aws/workload and
#     envs/gcp/workload (null when the bridge is on: TFE_TOKEN).
#   supabase access_token / vercel api_token: the placeholders in envs/saas
#     when a feature is off.
allowed_credential_references := {
	"aws/shared_config_files=var.tfc_aws_dynamic_credentials",
	"google/impersonate_service_account=var.terraform_admin_email",
	"google-beta/impersonate_service_account=var.terraform_admin_email",
	"tfe/token=var.enable_saas_secret_bridge",
	"supabase/access_token=local.enable_supabase",
	"supabase/access_token=local.supabase_disabled_placeholder_token",
	"vercel/api_token=local.enable_vercel",
	"vercel/api_token=local.vercel_disabled_placeholder_token",
}

# String literals that scripts/check-plan-time-exec.py accepts inside an
# allowed credential expression: inert placeholders, not credentials. (The
# plan JSON does not show literals inside an expression, so OPA cannot check
# this list.)
allowed_credential_literals := {"saas-bridge-disabled-placeholder"}

# Ephemeral resource types (Terraform 1.10+) a configuration may declare. An
# ephemeral resource is opened during the plan and the apply and runs provider
# code with the workspace's credentials. This repo uses only tfe_outputs (the
# SaaS secret bridge of envs/aws/workload and envs/gcp/workload).
allowed_ephemeral_types := {"tfe_outputs"}
