# MANDATORY: no provisioners outside the one reviewed module-call chain, no
# external / http / aws_lambda_invocation data sources anywhere, no action
# blocks outside allowed_action_types, only allowlisted providers and
# remote-state backends, and no provider endpoint, proxy, TLS or inline
# credential (credentials, token_url) overrides.
# The allowlists are in no_plan_time_code_execution_allowlist.rego. A plan runs with the workspace's
# credentials and environment variables (TFE_TOKEN, SUPABASE_ACCESS_TOKEN, the
# cloud plan identity). A data "external" or data "http" block and every
# provider binary run during the plan; a provisioner runs arbitrary commands
# during the apply; an endpoint override sends the credentials to another host.
#
# WHEN THIS RUNS. HCP Terraform evaluates policy sets after the plan. When this
# policy fails, a data "external" / "http" block, a non-allowlisted provider or
# a redirected provider endpoint has ALREADY run with the workspace's
# credentials. For those, this policy is a detective control: it marks the run
# and stops its apply. It is a preventive control only for what runs at apply
# time: provisioners, and writes through a redirected endpoint.
# The controls that act before the plan are scripts/check-plan-time-exec.py in
# CI (run by scripts/check-consistency.sh: it parses the repo's .tf and .tf.json
# files and applies the lists of this policy, plus removed blocks, dynamic
# provider blocks and module sources; it never sees a CLI upload) and
# tfc-admin's secret-bearing projects, where the platform team has
# runs = read (no plan) and pull requests get no speculative plan unless
# enable_speculative_on_secret_bearing is set.
#
# Plan JSON fields read (terraform show -json):
#   configuration.root_module(.module_calls.<name>.module)*.resources[i]
#     .mode, .type, .address, .provisioners[].type
#   configuration...module_calls.<name>.source   (the literal source string)
#   configuration.provider_config.<key>.full_name and .expressions
#     (one entry per provider configuration, including implied providers of
#     modules, keyed "<name>[.<alias>]" or "<module_address>:<name>")
#   resource_changes[].provider_name
#   ...resources[i].expressions.backend.constant_value (terraform_remote_state)
# Blind spots (docs/known-gaps.md):
#   - a `dynamic` block inside a provider block is not rendered in .expressions;
#   - endpoints set through environment variables, an AWS shared config or
#     credentials file (endpoint_url, credential_process) or a google
#     external_account credentials file (token_url) never appear in the plan;
#   - a `removed` block is not rendered at all, so a destroy-time provisioner
#     in it runs at apply without this policy seeing it. What limits it today:
#     scripts/check-plan-time-exec.py fails on a provisioner in any removed
#     block in the repo, and
#     confirming an apply needs apply rights (the platform team has runs =
#     read on secret-bearing projects);
#   - the policy does not pin the run's workspace: any workspace whose root
#     has the same two module calls and sources passes the provisioner rule.
#
# Provisioner allowlist: modules/supabase/vault-secrets (its reviewed bootstrap
# and reconcile provisioners), reached through the EXACT chain of module calls
# envs/saas -> saas_workload -> vault_secrets, with the exact source strings.
# A suffix match is not enough: ./evil/supabase/vault-secrets and
# git::https://x//supabase/vault-secrets both end the same way. A module
# nested below vault_secrets is not covered (vault-secrets calls no module).
package terraform.policies.no_plan_time_code_execution

import rego.v1

# Data sources that run code or call out during the plan: external runs a
# program, http fetches a URL, aws_lambda_invocation invokes a Lambda function.
exec_data_types := {"external", "http", "aws_lambda_invocation"}

allowed_provisioner_chain := [
	{"name": "saas_workload", "source": "../../modules/saas/stages/saas-workload"},
	{"name": "vault_secrets", "source": "../../../supabase/vault-secrets"},
]

# Provider arguments that redirect API calls, proxy them or weaken TLS:
# aws endpoints {} / custom_ca_bundle / insecure / *_proxy /
# ec2_metadata_service_endpoint, google *_custom_endpoint / universe_domain,
# tfe hostname / ssl_skip_verify, supabase endpoint, azurerm metadata_host.
# Inline credentials (google credentials, a token_url) swap the workspace's
# identity or send a token exchange to another host; no provider block in
# this repo sets them. access_token is not listed: envs/saas sets the supabase
# access_token to a placeholder when Supabase is off (docs/known-gaps.md).
endpoint_key_pattern := `^(endpoints?|.*_endpoint|hostname|base_url|api_url|metadata_host|universe_domain|custom_ca_bundle|insecure|ssl_skip_verify|skip_tls_verify|https?_proxy|no_proxy|credentials|token_url)$`

# Every resource block of the configuration, at any module depth, with its
# walk path.
config_resources contains [path, r] if {
	walk(input.plan.configuration, [path, r])
	n := count(path)
	n >= 2
	path[n - 2] == "resources"
	is_number(path[n - 1])
	is_object(r)
}

# The chain of module calls from the root to the resource: [{name, source}].
# path is root_module, (module_calls, <name>, module)*, resources, <i>.
call_chain(path) := [link |
	some j in numbers.range(0, count(path) - 2)
	path[j] == "module_calls"
	call := object.get(input.plan.configuration, array.slice(path, 0, j + 2), {})
	link := {"name": path[j + 1], "source": object.get(call, "source", "")}
]

provisioner_exempt(path) if call_chain(path) == allowed_provisioner_chain

# Absolute address for messages: configuration addresses are module-relative.
full_address(path, r) := concat("", array.concat(
	[sprintf("module.%s.", [link.name]) | some link in call_chain(path)],
	[object.get(r, "address", "?")],
))

deny contains msg if {
	some pair in config_resources
	path := pair[0]
	r := pair[1]
	some prov in object.get(r, "provisioners", [])
	not provisioner_exempt(path)
	msg := sprintf("%s: declares a %s provisioner (arbitrary commands at apply time with the workspace's credentials); only envs/saas -> module.saas_workload -> module.vault_secrets may", [full_address(path, r), object.get(prov, "type", "?")])
}

deny contains msg if {
	some pair in config_resources
	path := pair[0]
	r := pair[1]
	object.get(r, "mode", "") == "data"
	object.get(r, "type", "") in exec_data_types
	msg := sprintf("%s: data %q ran at plan time with the workspace's credentials and environment variables; it is not allowed", [full_address(path, r), r.type])
}

# A remote-state read runs a backend client with the workspace's environment
# during the plan: an http or s3 backend can send it to another host. The
# backend must be a literal on allowed_remote_state_backends.
deny contains msg if {
	some pair in config_resources
	path := pair[0]
	r := pair[1]
	object.get(r, "mode", "") == "data"
	object.get(r, "type", "") == "terraform_remote_state"
	not object.get(r, ["expressions", "backend", "constant_value"], null) in allowed_remote_state_backends
	msg := sprintf("%s: terraform_remote_state backend must be a literal %v, not %v", [full_address(path, r), sort(allowed_remote_state_backends), object.get(r, ["expressions", "backend"], null)])
}

deny contains msg if {
	some key, pc in object.get(input.plan.configuration, "provider_config", {})
	not object.get(pc, "full_name", "") in allowed_provider_sources
	msg := sprintf("provider %s (%s) is not on the provider allowlist; a provider binary runs at plan time with the workspace's environment", [key, object.get(pc, "full_name", "?")])
}

deny contains msg if {
	some rc in object.get(input.plan, "resource_changes", [])
	not object.get(rc, "provider_name", "") in allowed_provider_sources
	msg := sprintf("%s: provider %s is not on the provider allowlist", [object.get(rc, "address", "?"), object.get(rc, "provider_name", "?")])
}

endpoint_override(attr) if {
	regex.match(endpoint_key_pattern, attr)
	not attr in endpoint_key_exceptions
}

deny contains msg if {
	some key, pc in object.get(input.plan.configuration, "provider_config", {})
	some attr, _ in object.get(pc, "expressions", {})
	endpoint_override(attr)
	msg := sprintf("provider %s sets %q: an endpoint, proxy or TLS override can send the workspace's credentials to another host", [key, attr])
}

# Every action block of the configuration (Terraform 1.14+), at any module
# depth: configuration...actions[i] with .type and .address (verified with
# Terraform 1.17.1). An action runs provider code at apply time, for example
# aws_lambda_invoke. Only types on allowed_action_types may appear.
deny contains msg if {
	walk(input.plan.configuration, [path, a])
	n := count(path)
	n >= 2
	path[n - 2] == "actions"
	is_number(path[n - 1])
	is_object(a)
	not object.get(a, "type", "") in allowed_action_types
	msg := sprintf("%s: action type %q is not on allowed_action_types; an action runs provider code at apply time", [object.get(a, "address", "?"), object.get(a, "type", "?")])
}
