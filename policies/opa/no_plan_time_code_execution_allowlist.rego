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
# sets, as "<provider type>/<argument>=<reference path>". The argument is
# allowed when every reference of its expression is EXACTLY one of these
# paths; [*] stands for one literal map key (["backup"]). A path below an
# entry is not allowed: an optional attribute with a default inside the
# variable type would otherwise carry a value the plan does not show.
#   aws shared_config_files: the TFC dynamic-credentials file of
#     envs/aws/security and envs/aws/backup (multi-account roots).
#   google / google-beta impersonate_service_account: every GCP root (null in
#     HCP Terraform; set for deliberate local runs).
#   tfe token: the SaaS bridge placeholder in envs/aws/workload and
#     envs/gcp/workload (null when the bridge is on: TFE_TOKEN).
#   supabase access_token / vercel api_token: the inline placeholders in
#     envs/saas when a feature is off.
# The variable values are checked by credential_variable_value_ok in
# no_plan_time_code_execution.rego.
allowed_credential_references := {
	"aws/shared_config_files=var.tfc_aws_dynamic_credentials",
	"aws/shared_config_files=var.tfc_aws_dynamic_credentials.default",
	"aws/shared_config_files=var.tfc_aws_dynamic_credentials.default.shared_config_file",
	"aws/shared_config_files=var.tfc_aws_dynamic_credentials.aliases",
	"aws/shared_config_files=var.tfc_aws_dynamic_credentials.aliases[*]",
	"aws/shared_config_files=var.tfc_aws_dynamic_credentials.aliases[*].shared_config_file",
	"google/impersonate_service_account=var.terraform_admin_email",
	"google-beta/impersonate_service_account=var.terraform_admin_email",
	"tfe/token=var.enable_saas_secret_bridge",
	"supabase/access_token=local.enable_supabase",
	"vercel/api_token=local.enable_vercel",
}

# The type each variable on allowed_credential_references must declare, as
# "<name>=<type>" (compared token by token, so spacing does not matter).
# Checked by scripts/check-plan-time-exec.py only: the plan JSON does not
# show variable types. An optional() attribute with a default would add a
# value the plan's variable value does not show.
allowed_credential_variable_types := {
	"tfc_aws_dynamic_credentials=object({default=object({shared_config_file=string}),aliases=map(object({shared_config_file=string}))})",
	"terraform_admin_email=string",
	"enable_saas_secret_bridge=bool",
}

# String literals that scripts/check-plan-time-exec.py accepts inside an
# allowed credential expression: inert placeholders, not credentials (the
# tfe bridge placeholder, and the envs/saas Supabase and Vercel placeholders,
# which are format-valid so that provider configuration passes). The plan
# JSON does not show literals inside an expression, so OPA cannot check this
# list.
allowed_credential_literals := {
	"saas-bridge-disabled-placeholder",
	"sbp_disabled_placeholder",
	"000000000000000000000000",
}

# Ephemeral resource types (Terraform 1.10+) a configuration may declare. An
# ephemeral resource is opened during the plan and the apply and runs provider
# code with the workspace's credentials. This repo uses only tfe_outputs (the
# SaaS secret bridge of envs/aws/workload and envs/gcp/workload).
allowed_ephemeral_types := {"tfe_outputs"}

# Re-audit 7 SEC-1 to SEC-3: resource and data-source arguments that take a
# path on the runner, which the provider reads at plan or apply and uploads.
# Each may only hold a path under path.module (or the output_path of a
# reviewed archive_file). "<type>.<argument>".
# The list follows the provider schemas (aws 6.72, google 8.10, tfe 0.83,
# vercel 4.8.2, supabase 1.9.1): re-check it on every provider upgrade
# (docs/known-gaps.md).
path_reading_attributes := {
	"aws_connect_contact_flow.filename",
	"aws_connect_contact_flow_module.filename",
	"aws_gamelift_script.zip_file",
	"aws_lambda_function.filename",
	"aws_lambda_layer_version.filename",
	"aws_rds_custom_db_engine_version.filename",
	"aws_s3_bucket_object.source",
	"aws_s3_object.source",
	"aws_synthetics_canary.zip_file",
	"google_apigee_api.config_bundle",
	"google_apigee_keystores_aliases_pkcs12.file",
	"google_apigee_sharedflow.config_bundle",
	"google_storage_bucket_object.source",
	"supabase_edge_function.entrypoint",
	"supabase_edge_function.import_map",
	"supabase_edge_function.static_files",
	"tfe_slug.source_path",
	"vercel_blob_object.source",
}

# Arguments that upload local files and that this repo never uses: refused
# outright (a vercel_deployment files map, a pre-built policy-set slug).
refused_path_attributes := {
	"tfe_policy_set.slug",
	"vercel_deployment.files",
	"vercel_deployment.path_prefix",
}
