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
		"supabase": prov("supabase", "registry.terraform.io/supabase/supabase", {"access_token": {"references": ["local.enable_supabase", "local.supabase_disabled_placeholder_token"]}}),
		"vercel": prov("vercel", "registry.terraform.io/vercel/vercel", {"api_token": {"references": ["local.enable_vercel", "local.vercel_disabled_placeholder_token"]}}),
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

# ── More endpoint keys ─────────────────────────────────────────────────────
test_base_url_denied if {
	count(p.deny) == 1 with input as with_providers({"vercel": prov("vercel", "registry.terraform.io/vercel/vercel", {"base_url": {"constant_value": "https://attacker.example"}})})
}

test_api_url_denied if {
	count(p.deny) == 1 with input as with_providers({"supabase": prov("supabase", "registry.terraform.io/supabase/supabase", {"api_url": {"constant_value": "https://attacker.example"}})})
}

test_metadata_host_denied if {
	count(p.deny) == 1 with input as with_providers({"azurerm": prov("azurerm", "registry.terraform.io/hashicorp/azurerm", {"metadata_host": {"constant_value": "attacker.example"}})})
}

test_insecure_denied if {
	count(p.deny) == 1 with input as with_providers({"aws": prov("aws", "registry.terraform.io/hashicorp/aws", {"insecure": {"constant_value": true}})})
}

test_skip_tls_verify_denied if {
	count(p.deny) == 1 with input as with_providers({"aws": prov("aws", "registry.terraform.io/hashicorp/aws", {"skip_tls_verify": {"constant_value": true}})})
}

test_no_proxy_denied if {
	count(p.deny) == 1 with input as with_providers({"aws": prov("aws", "registry.terraform.io/hashicorp/aws", {"no_proxy": {"constant_value": "*"}})})
}

test_azurerm_allowed if {
	count(p.deny) == 0 with input as with_providers({"azurerm": prov("azurerm", "registry.terraform.io/hashicorp/azurerm", {"features": [{}]})})
}

# An enum (regional / legacy), not a host name.
test_s3_us_east_1_regional_endpoint_allowed if {
	count(p.deny) == 0 with input as with_providers({"aws": prov("aws", "registry.terraform.io/hashicorp/aws", {"s3_us_east_1_regional_endpoint": {"constant_value": "regional"}})})
}

# ── terraform_remote_state backends ────────────────────────────────────────
remote_state(backend_expr) := in_root([{
	"address": "data.terraform_remote_state.x", "mode": "data", "type": "terraform_remote_state", "name": "x",
	"expressions": {"backend": backend_expr, "config": {"constant_value": {}}},
}])

test_remote_state_cloud_allowed if count(p.deny) == 0 with input as remote_state({"constant_value": "cloud"})

test_remote_state_remote_allowed if count(p.deny) == 0 with input as remote_state({"constant_value": "remote"})

test_remote_state_http_denied if count(p.deny) == 1 with input as remote_state({"constant_value": "http"})

test_remote_state_s3_denied if count(p.deny) == 1 with input as remote_state({"constant_value": "s3"})

test_remote_state_backend_reference_denied if count(p.deny) == 1 with input as remote_state({"references": ["var.backend"]})

test_remote_state_in_module_denied if {
	count(p.deny) == 1 with input as in_module("../x", [{
		"address": "data.terraform_remote_state.x", "mode": "data", "type": "terraform_remote_state", "name": "x",
		"expressions": {"backend": {"constant_value": "http"}},
	}])
}

# ── Review follow-up: lambda data source, actions, inline credentials ───────
test_lambda_invocation_data_denied if count(p.deny) == 1 with input as in_root([data_source("aws_lambda_invocation")])

test_lambda_invoke_action_denied if {
	inp := {"plan": {"configuration": {"root_module": {"actions": [{"address": "action.aws_lambda_invoke.a", "type": "aws_lambda_invoke", "name": "a", "provider_config_key": "aws"}]}}}}
	count(p.deny) == 1 with input as inp
}

test_action_in_module_denied if {
	inp := {"plan": {"configuration": {"root_module": {"module_calls": {"m": {"source": "../x", "module": {"actions": [{"address": "action.aws_lambda_invoke.a", "type": "aws_lambda_invoke"}]}}}}}}}
	count(p.deny) == 1 with input as inp
}

test_google_credentials_denied if {
	count(p.deny) == 1 with input as with_providers({"google": prov("google", "registry.terraform.io/hashicorp/google", {"credentials": {"references": ["var.creds"]}})})
}

# envs/saas sets the supabase access_token (a placeholder when Supabase is off).
test_supabase_access_token_allowed if {
	count(p.deny) == 0 with input as with_providers({"supabase": prov("supabase", "registry.terraform.io/supabase/supabase", {"access_token": {"references": ["local.enable_supabase", "local.supabase_disabled_placeholder_token"]}})})
}

test_token_url_denied if {
	count(p.deny) == 1 with input as with_providers({"google": prov("google", "registry.terraform.io/hashicorp/google", {"token_url": {"constant_value": "https://attacker.example/token"}})})
}

# A credentials file can name a credential_process too (SEC-1).
test_shared_credentials_files_denied if {
	count(p.deny) == 1 with input as with_providers({"aws": prov("aws", "registry.terraform.io/hashicorp/aws", {"shared_credentials_files": {"constant_value": ["/x"]}})})
}

# ── SEC-1: credential, profile and identity arguments ──────────────────────
# Fixtures copied from `terraform show -json` of scratch roots planned with
# Terraform 1.17.1, aws 6.72.0, google 8.10.0, tfe 0.83.0, supabase 1.9.1 and
# vercel 4.8.2. The plan of the first one ran the credential_process of the
# committed aws.cfg (it created a marker file), and the policy before this
# rule returned no deny.
aws_source := "registry.terraform.io/hashicorp/aws"

with_root(pc, variables) := {"plan": {"configuration": {"root_module": {"variables": variables}, "provider_config": pc}}}

# The reviewer's bypass: profile + a committed shared config file.
sec1_profile := {"aws": {
	"name": "aws", "full_name": aws_source, "version_constraint": "6.72.0",
	"expressions": {
		"profile": {"constant_value": "pwn"},
		"shared_config_files": {"constant_value": ["./aws.cfg"]},
		"skip_credentials_validation": {"constant_value": true},
		"skip_metadata_api_check": {"constant_value": true},
		"skip_requesting_account_id": {"constant_value": true},
	},
}}

test_sec1_profile_and_shared_config_denied if {
	msgs := p.deny with input as with_root(sec1_profile, {})
	count(msgs) == 2
	some m1 in msgs
	contains(m1, `"profile"`)
	some m2 in msgs
	contains(m2, `"shared_config_files"`)
}

# The form envs/aws/security and envs/aws/backup use (real plan JSON).
dynamic_credentials_provider := {
	"name": "aws", "full_name": aws_source, "alias": "backup", "version_constraint": "6.72.0",
	"expressions": {
		"region": {"constant_value": "eu-west-2"},
		"shared_config_files": {"references": [
			"var.tfc_aws_dynamic_credentials",
			"var.tfc_aws_dynamic_credentials.aliases[\"backup\"].shared_config_file",
			"var.tfc_aws_dynamic_credentials.aliases[\"backup\"]",
			"var.tfc_aws_dynamic_credentials.aliases",
			"var.tfc_aws_dynamic_credentials",
		]},
	},
}

test_dynamic_credentials_shared_config_allowed if {
	count(p.deny) == 0 with input as with_root({"aws.backup": dynamic_credentials_provider}, {"tfc_aws_dynamic_credentials": {"default": null}})
}

# A default would feed a committed file to the provider whenever HCP Terraform
# does not inject the variable (local runs, dynamic credentials off).
test_dynamic_credentials_with_default_denied if {
	vars := {"tfc_aws_dynamic_credentials": {"default": {"default": {"shared_config_file": "./aws.cfg"}, "aliases": {}}}}
	count(p.deny) == 1 with input as with_root({"aws.backup": dynamic_credentials_provider}, vars)
}

test_shared_config_from_another_variable_denied if {
	pc := {"aws": prov("aws", aws_source, {"shared_config_files": {"references": ["var.tfc_aws_dynamic_credentials", "var.cfg"]}})}
	count(p.deny) == 1 with input as with_root(pc, {"tfc_aws_dynamic_credentials": {"default": null}, "cfg": {"default": null}})
}

# A look-alike variable name is not the allowed one.
test_shared_config_lookalike_variable_denied if {
	pc := {"aws": prov("aws", aws_source, {"shared_config_files": {"references": ["var.tfc_aws_dynamic_credentials_x"]}})}
	count(p.deny) == 1 with input as with_root(pc, {"tfc_aws_dynamic_credentials_x": {"default": null}})
}

# The allowance is per provider and argument: the same reference does not
# allow shared_credentials_files.
test_shared_credentials_from_dynamic_credentials_denied if {
	pc := {"aws": prov("aws", aws_source, {"shared_credentials_files": {"references": ["var.tfc_aws_dynamic_credentials"]}})}
	count(p.deny) == 1 with input as with_root(pc, {"tfc_aws_dynamic_credentials": {"default": null}})
}

test_aws_static_keys_denied if {
	pc := {"aws.legit": prov("aws", aws_source, {
		"access_key": {"constant_value": "AKIAEXAMPLEEXAMPLE00"},
		"secret_key": {"constant_value": "x"},
		"token": {"constant_value": "t"},
	})}
	count(p.deny) == 3 with input as with_root(pc, {})
}

test_aws_web_identity_denied if {
	pc := {"aws": prov("aws", aws_source, {"assume_role_with_web_identity": [{
		"role_arn": {"constant_value": "arn:aws:iam::111111111111:role/x"},
		"web_identity_token_file": {"constant_value": "./token"},
	}]})}
	count(p.deny) == 1 with input as with_root(pc, {})
}

# A null argument (the provider reads its environment) is not an override.
test_null_credential_allowed if {
	pc := {"google": prov("google", "registry.terraform.io/hashicorp/google", {"access_token": {"constant_value": null}})}
	count(p.deny) == 0 with input as with_root(pc, {})
}

# Every GCP root impersonates var.terraform_admin_email (default null).
test_gcp_impersonation_from_variable_allowed if {
	pc := {
		"google": prov("google", "registry.terraform.io/hashicorp/google", {"impersonate_service_account": {"references": ["var.terraform_admin_email"]}}),
		"google-beta": prov("google-beta", "registry.terraform.io/hashicorp/google-beta", {"impersonate_service_account": {"references": ["var.terraform_admin_email"]}}),
	}
	count(p.deny) == 0 with input as with_root(pc, {"terraform_admin_email": {"default": null}})
}

test_gcp_impersonation_literal_denied if {
	pc := {"google.lit": prov("google", "registry.terraform.io/hashicorp/google", {
		"access_token": {"constant_value": null},
		"impersonate_service_account": {"constant_value": "evil@attacker.iam.gserviceaccount.com"},
		"external_credentials": [{
			"audience": {"constant_value": "//iam.googleapis.com/x"},
			"identity_token": {"constant_value": "t"},
			"service_account_email": {"constant_value": "x@y.iam.gserviceaccount.com"},
		}],
	})}
	msgs := p.deny with input as with_root(pc, {})
	count(msgs) == 2
}

test_gcp_impersonation_with_default_denied if {
	pc := {"google": prov("google", "registry.terraform.io/hashicorp/google", {"impersonate_service_account": {"references": ["var.terraform_admin_email"]}})}
	count(p.deny) == 1 with input as with_root(pc, {"terraform_admin_email": {"default": "evil@attacker.iam.gserviceaccount.com"}})
}

test_gcp_impersonation_delegates_denied if {
	pc := {"google": prov("google", "registry.terraform.io/hashicorp/google", {"impersonate_service_account_delegates": {"constant_value": ["a@b.iam.gserviceaccount.com"]}})}
	count(p.deny) == 1 with input as with_root(pc, {})
}

# envs/aws/workload and envs/gcp/workload: the bridge token placeholder.
test_tfe_bridge_token_allowed if {
	pc := {"tfe": prov("tfe", "registry.terraform.io/hashicorp/tfe", {"token": {"references": ["var.enable_saas_secret_bridge"]}})}
	count(p.deny) == 0 with input as with_root(pc, {"enable_saas_secret_bridge": {"default": false}})
}

test_tfe_literal_token_denied if {
	pc := {"tfe": prov("tfe", "registry.terraform.io/hashicorp/tfe", {"token": {"constant_value": "attacker-token"}})}
	count(p.deny) == 1 with input as with_root(pc, {})
}

# The allowance names the provider type: an aws token is not a tfe token.
test_aws_token_from_bridge_switch_denied if {
	pc := {"aws": prov("aws", aws_source, {"token": {"references": ["var.enable_saas_secret_bridge"]}})}
	count(p.deny) == 1 with input as with_root(pc, {"enable_saas_secret_bridge": {"default": false}})
}

test_vercel_token_from_other_local_denied if {
	pc := {"vercel": prov("vercel", "registry.terraform.io/vercel/vercel", {"api_token": {"references": ["local.attacker_token"]}})}
	count(p.deny) == 1 with input as with_root(pc, {})
}

# A function call with no reference shows neither a constant nor references.
test_credential_without_references_denied if {
	pc := {"aws": prov("aws", aws_source, {"shared_config_files": {}})}
	count(p.deny) == 1 with input as with_root(pc, {})
}

# A provider block inside a called module gets no allowance.
test_module_provider_credential_denied if {
	pc := {"module.m:google": {
		"name": "google", "full_name": "registry.terraform.io/hashicorp/google", "module_address": "module.m",
		"expressions": {"impersonate_service_account": {"references": ["var.terraform_admin_email"]}},
	}}
	count(p.deny) == 1 with input as with_root(pc, {"terraform_admin_email": {"default": null}})
}

# ── SEC-2: ephemeral resources ─────────────────────────────────────────────
# The plan JSON has no entry for an ephemeral block. Its type shows only in the
# references of the expressions that use it (real plan JSON below). An
# ephemeral block that nothing references, or that is reached through a local,
# is invisible here; scripts/check-plan-time-exec.py checks the blocks.
ephemeral_use(type) := {"plan": {"configuration": {
	"provider_config": {"aws.role": prov("aws", aws_source, {"region": {"constant_value": "eu-west-2"}})},
	"root_module": {"resources": [{
		"address": "aws_secretsmanager_secret_version.v", "mode": "managed", "type": "aws_secretsmanager_secret_version", "name": "v",
		"provider_config_key": "aws.legit",
		"expressions": {
			"secret_id": {"constant_value": "s"},
			"secret_string_wo": {"references": [sprintf("ephemeral.%s.x.result", [type]), sprintf("ephemeral.%s.x", [type])]},
			"secret_string_wo_version": {"constant_value": 1},
		},
		"schema_version": 0,
	}]},
}}}

test_ephemeral_token_minting_denied if {
	msgs := p.deny with input as ephemeral_use("google_service_account_access_token")
	count(msgs) == 1
	some m in msgs
	contains(m, "google_service_account_access_token")
}

test_ephemeral_lambda_invocation_denied if count(p.deny) == 1 with input as ephemeral_use("aws_lambda_invocation")

test_ephemeral_random_password_denied if count(p.deny) == 1 with input as ephemeral_use("random_password")

# The SaaS bridge (envs/aws/workload, envs/gcp/workload) reads tfe_outputs
# through a module argument.
test_ephemeral_tfe_outputs_allowed if {
	inp := {"plan": {"configuration": {"root_module": {"module_calls": {"saas_bridge": {
		"source": "../../modules/x",
		"expressions": {"values": {"references": ["ephemeral.tfe_outputs.saas[0].values.supabase_api_url", "ephemeral.tfe_outputs.saas[0].values", "ephemeral.tfe_outputs.saas[0]", "ephemeral.tfe_outputs.saas"]}},
		"module": {},
	}}}}}}
	count(p.deny) == 0 with input as inp
}

test_ephemeral_in_provider_config_denied if {
	pc := {"aws.role": prov("aws", aws_source, {"region": {"constant_value": "eu-west-2"}, "secret_key": {"references": ["ephemeral.random_password.x.result", "ephemeral.random_password.x"]}})}
	# one deny for the secret_key argument, one for the ephemeral type
	count(p.deny) == 2 with input as with_root(pc, {})
}
