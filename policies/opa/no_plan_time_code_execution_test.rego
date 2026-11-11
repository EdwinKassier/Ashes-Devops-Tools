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

# A look-alike source does not match the allowlist.
test_lookalike_source_denied if count(p.deny) == 1 with input as in_module("../evil-supabase/vault-secrets-copy", [local_exec("terraform_data.x")])

# A module nested below a vault-secrets call is not on the allowlist.
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

# ── Attack corpus: allowlist look-alikes ───────────────────────────────────
# root -> saas_workload (outer_source) -> inner_name (inner_source) -> resources
saas_chain(outer_source, inner_name, inner_source, resources) := {"plan": {"configuration": {"root_module": {"module_calls": {"saas_workload": {
	"source": outer_source,
	"module": {"module_calls": {inner_name: {
		"source": inner_source,
		"module": {"resources": resources},
	}}},
}}}}}}

saas_outer := "../../modules/saas/stages/saas-workload"

saas_inner := "../../../supabase/vault-secrets"

test_exact_saas_chain_allowed if {
	count(p.deny) == 0 with input as saas_chain(saas_outer, "vault_secrets", saas_inner, [local_exec("terraform_data.bootstrap")])
}

test_dot_slash_evil_suffix_denied if count(p.deny) == 1 with input as in_module("./evil/supabase/vault-secrets", [local_exec("terraform_data.x")])

test_git_suffix_denied if count(p.deny) == 1 with input as in_module("git::https://attacker.example/x.git//supabase/vault-secrets", [local_exec("terraform_data.x")])

test_registry_suffix_denied if count(p.deny) == 1 with input as in_module("app.terraform.io/acme/supabase/vault-secrets", [local_exec("terraform_data.x")])

test_evil_sibling_dir_denied if count(p.deny) == 1 with input as in_module("../../modules/supabase/vault-secrets-evil", [local_exec("terraform_data.x")])

# The real module, but called straight from a root instead of through saas-workload.
test_direct_root_call_denied if count(p.deny) == 1 with input as in_module("../../modules/supabase/vault-secrets", [local_exec("terraform_data.x")])

test_trailing_slash_denied if count(p.deny) == 1 with input as in_module("../../modules/supabase/vault-secrets/", [local_exec("terraform_data.x")])

test_renamed_call_denied if {
	count(p.deny) == 1 with input as saas_chain(saas_outer, "vault", saas_inner, [local_exec("terraform_data.x")])
}

test_wrong_outer_source_denied if {
	count(p.deny) == 1 with input as saas_chain("./evil/saas/stages/saas-workload", "vault_secrets", saas_inner, [local_exec("terraform_data.x")])
}

test_git_inner_source_in_saas_chain_denied if {
	count(p.deny) == 1 with input as saas_chain(saas_outer, "vault_secrets", "git::https://attacker.example/x.git//supabase/vault-secrets", [local_exec("terraform_data.x")])
}

# A provisioner in the saas-workload stage itself (one level up) is not allowed.
test_provisioner_in_saas_workload_denied if {
	inp := {"plan": {"configuration": {"root_module": {"module_calls": {"saas_workload": {
		"source": saas_outer,
		"module": {"resources": [local_exec("terraform_data.x")]},
	}}}}}}
	count(p.deny) == 1 with input as inp
}

# A module nested below the exact allowed chain is not allowed: vault-secrets
# calls no module, so anything below it is unreviewed code.
test_nested_below_exact_chain_denied if {
	inp := {"plan": {"configuration": {"root_module": {"module_calls": {"saas_workload": {
		"source": saas_outer,
		"module": {"module_calls": {"vault_secrets": {
			"source": saas_inner,
			"module": {"module_calls": {"inner": {
				"source": "./inner",
				"module": {"resources": [local_exec("terraform_data.x")]},
			}}},
		}}},
	}}}}}}
	count(p.deny) == 1 with input as inp
}

# Data sources are never exempt, even in the reviewed chain.
test_http_data_in_saas_chain_denied if {
	count(p.deny) == 1 with input as saas_chain(saas_outer, "vault_secrets", saas_inner, [data_source("http")])
}

test_external_data_in_saas_chain_denied if {
	count(p.deny) == 1 with input as saas_chain(saas_outer, "vault_secrets", saas_inner, [data_source("external")])
}

# ── Provider allowlist and endpoint overrides ──────────────────────────────
# Shapes follow `terraform show -json` (configuration.provider_config): one
# entry per provider config, keyed "<name>[.<alias>]" in the root and
# "<module_address>:<name>" for an implied provider in a module.
with_providers(pc) := {"plan": {"configuration": {"root_module": {}, "provider_config": pc}}}

prov(name, full_name, expressions) := {"name": name, "full_name": full_name, "expressions": expressions}

test_allowed_providers_pass if {
	count(p.deny) == 0 with input as with_providers({
		"aws": prov("aws", "registry.terraform.io/hashicorp/aws", {"region": {"constant_value": "eu-west-2"}}),
		"aws.log_archive": prov("aws", "registry.terraform.io/hashicorp/aws", {"assume_role": [{"role_arn": {"references": ["var.x"]}}]}),
		"tfe": prov("tfe", "registry.terraform.io/hashicorp/tfe", {"organization": {"references": ["local.org"]}}),
		"google": prov("google", "registry.terraform.io/hashicorp/google", {"project": {"constant_value": "p"}}),
		"google-beta": prov("google-beta", "registry.terraform.io/hashicorp/google-beta", {}),
		"supabase": prov("supabase", "registry.terraform.io/supabase/supabase", {"access_token": {"references": ["local.x"]}}),
		"vercel": prov("vercel", "registry.terraform.io/vercel/vercel", {"api_token": {"references": ["local.x"]}}),
		"random": {"name": "random", "full_name": "registry.terraform.io/hashicorp/random"},
		"null": {"name": "null", "full_name": "registry.terraform.io/hashicorp/null"},
		"archive": {"name": "archive", "full_name": "registry.terraform.io/hashicorp/archive"},
		"module.saas_workload.module.vault_secrets:terraform": {"name": "terraform", "full_name": "terraform.io/builtin/terraform", "module_address": "module.saas_workload.module.vault_secrets"},
	})
}

test_external_provider_denied if {
	count(p.deny) == 1 with input as with_providers({"external": {"name": "external", "full_name": "registry.terraform.io/hashicorp/external"}})
}

test_http_provider_denied if {
	count(p.deny) == 1 with input as with_providers({"http": {"name": "http", "full_name": "registry.terraform.io/hashicorp/http"}})
}

test_third_party_provider_denied if {
	count(p.deny) == 1 with input as with_providers({"x": {"name": "x", "full_name": "registry.terraform.io/attacker/exfil"}})
}

# Same type name as an allowed provider, from another namespace.
test_lookalike_namespace_denied if {
	count(p.deny) == 1 with input as with_providers({"aws": {"name": "aws", "full_name": "registry.terraform.io/attacker/aws"}})
}

test_private_registry_provider_denied if {
	count(p.deny) == 1 with input as with_providers({"aws": {"name": "aws", "full_name": "app.terraform.io/acme/aws"}})
}

test_implied_module_provider_denied if {
	count(p.deny) == 1 with input as with_providers({"module.m:exfil": {"name": "exfil", "full_name": "registry.terraform.io/attacker/exfil", "module_address": "module.m"}})
}

test_resource_change_from_unlisted_provider_denied if {
	inp := {"plan": {"configuration": {"root_module": {}}, "resource_changes": [{
		"address": "dns_a_record_set.x", "mode": "managed", "type": "dns_a_record_set",
		"provider_name": "registry.terraform.io/hashicorp/dns",
		"change": {"actions": ["create"], "after": {}, "after_unknown": {}},
	}]}}
	count(p.deny) == 1 with input as inp
}

test_resource_change_from_allowed_provider_passes if {
	inp := {"plan": {"configuration": {"root_module": {}}, "resource_changes": [
		{
			"address": "random_id.x", "mode": "managed", "type": "random_id",
			"provider_name": "registry.terraform.io/hashicorp/random",
			"change": {"actions": ["create"], "after": {}, "after_unknown": {}},
		},
		{
			"address": "terraform_data.x", "mode": "managed", "type": "terraform_data",
			"provider_name": "terraform.io/builtin/terraform",
			"change": {"actions": ["create"], "after": {}, "after_unknown": {}},
		},
	]}}
	count(p.deny) == 0 with input as inp
}

test_aws_endpoints_override_denied if {
	count(p.deny) == 1 with input as with_providers({"aws": prov("aws", "registry.terraform.io/hashicorp/aws", {"endpoints": [{"sts": {"constant_value": "https://attacker.example"}}]})})
}

test_aws_proxy_denied if {
	count(p.deny) == 1 with input as with_providers({"aws": prov("aws", "registry.terraform.io/hashicorp/aws", {"https_proxy": {"constant_value": "http://attacker.example:3128"}})})
}

test_aws_custom_ca_bundle_denied if {
	count(p.deny) == 1 with input as with_providers({"aws": prov("aws", "registry.terraform.io/hashicorp/aws", {"custom_ca_bundle": {"constant_value": "/tmp/ca.pem"}})})
}

test_google_custom_endpoint_denied if {
	count(p.deny) == 1 with input as with_providers({"google": prov("google", "registry.terraform.io/hashicorp/google", {"secret_manager_custom_endpoint": {"constant_value": "https://attacker.example/"}})})
}

test_google_universe_domain_denied if {
	count(p.deny) == 1 with input as with_providers({"google-beta": prov("google-beta", "registry.terraform.io/hashicorp/google-beta", {"universe_domain": {"constant_value": "attacker.example"}})})
}

test_tfe_hostname_denied if {
	count(p.deny) == 1 with input as with_providers({"tfe": prov("tfe", "registry.terraform.io/hashicorp/tfe", {"hostname": {"constant_value": "attacker.example"}})})
}

test_tfe_ssl_skip_verify_denied if {
	count(p.deny) == 1 with input as with_providers({"tfe": prov("tfe", "registry.terraform.io/hashicorp/tfe", {"ssl_skip_verify": {"constant_value": true}})})
}

test_supabase_endpoint_denied if {
	count(p.deny) == 1 with input as with_providers({"supabase": prov("supabase", "registry.terraform.io/supabase/supabase", {"endpoint": {"constant_value": "https://attacker.example"}})})
}

# An endpoint set from a variable is denied too: the key, not the value, decides.
test_endpoint_from_variable_denied if {
	count(p.deny) == 1 with input as with_providers({"supabase": prov("supabase", "registry.terraform.io/supabase/supabase", {"endpoint": {"references": ["var.endpoint"]}})})
}

# A legacy provider block inside a module is checked like a root one.
test_module_provider_endpoint_denied if {
	count(p.deny) == 1 with input as with_providers({"module.m:aws": {
		"name": "aws", "full_name": "registry.terraform.io/hashicorp/aws", "module_address": "module.m",
		"expressions": {"endpoints": [{"s3": {"constant_value": "https://attacker.example"}}]},
	}})
}

test_fips_switch_allowed if {
	count(p.deny) == 0 with input as with_providers({"aws": prov("aws", "registry.terraform.io/hashicorp/aws", {"use_fips_endpoint": {"constant_value": true}, "use_dualstack_endpoint": {"constant_value": false}})})
}

# Messages name the absolute address (configuration addresses are module-relative).
test_message_names_module_path if {
	msgs := p.deny with input as saas_chain(saas_outer, "vault", saas_inner, [local_exec("terraform_data.x")])
	some m in msgs
	startswith(m, "module.saas_workload.module.vault.terraform_data.x: ")
}
