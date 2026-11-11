package terraform.policies.no_plan_time_code_execution_test

import rego.v1

import data.terraform.policies.no_plan_time_code_execution as p

local_exec(address) := {
	"address": address, "mode": "managed", "type": "terraform_data", "name": "x",
	"provisioners": [{"type": "local-exec", "expressions": {"command": {"constant_value": "curl x"}}}],
}

data_source(type) := {"address": sprintf("data.%s.x", [type]), "mode": "data", "type": type, "name": "x"}

in_root(resources) := {"plan": {"configuration": {"root_module": {"resources": resources}}}}

# root -> module "<name>" (source) -> resources
in_module(source, resources) := {"plan": {"configuration": {"root_module": {"module_calls": {"m": {
	"source": source,
	"module": {"resources": resources},
}}}}}}

test_root_provisioner_denied if count(p.deny) == 1 with input as in_root([local_exec("terraform_data.x")])

test_module_provisioner_denied if count(p.deny) == 1 with input as in_module("../../modules/gcp/project", [local_exec("terraform_data.x")])

test_external_data_denied if count(p.deny) == 1 with input as in_root([data_source("external")])

test_http_data_denied if count(p.deny) == 1 with input as in_module("../vpc", [data_source("http")])

test_vault_secrets_provisioner_allowed if count(p.deny) == 0 with input as in_module("../../../supabase/vault-secrets", [local_exec("terraform_data.bootstrap")])

test_vault_secrets_trailing_slash_allowed if count(p.deny) == 0 with input as in_module("../../modules/supabase/vault-secrets/", [local_exec("terraform_data.bootstrap")])

# A look-alike source does not match the allowlist.
test_lookalike_source_denied if count(p.deny) == 1 with input as in_module("../evil-supabase/vault-secrets-copy", [local_exec("terraform_data.x")])

# The allowlist covers resources declared directly in vault-secrets only, not
# a module nested below it.
test_nested_below_vault_secrets_denied if {
	inp := {"plan": {"configuration": {"root_module": {"module_calls": {"vs": {
		"source": "../supabase/vault-secrets",
		"module": {"module_calls": {"inner": {
			"source": "./inner",
			"module": {"resources": [local_exec("terraform_data.x")]},
		}}},
	}}}}}}
	count(p.deny) == 1 with input as inp
}

# Two levels deep, as in envs/saas -> saas-workload -> vault-secrets.
test_deep_vault_secrets_allowed if {
	inp := {"plan": {"configuration": {"root_module": {"module_calls": {"saas_workload": {
		"source": "../../modules/saas/stages/saas-workload",
		"module": {
			"resources": [{"address": "supabase_project.this", "mode": "managed", "type": "supabase_project"}],
			"module_calls": {"vault_secrets": {
				"source": "../../../supabase/vault-secrets",
				"module": {"resources": [local_exec("terraform_data.bootstrap"), local_exec("terraform_data.reconcile")]},
			}},
		},
	}}}}}}
	count(p.deny) == 0 with input as inp
}

test_plain_resources_allowed if count(p.deny) == 0 with input as in_root([{"address": "google_project.x", "mode": "managed", "type": "google_project"}])

test_no_configuration_allowed if count(p.deny) == 0 with input as {"plan": {"resource_changes": []}}
