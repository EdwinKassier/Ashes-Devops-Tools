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
