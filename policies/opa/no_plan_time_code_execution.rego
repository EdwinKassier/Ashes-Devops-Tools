# MANDATORY: no provisioners outside the one reviewed module-call chain, no
# external / http / aws_lambda_invocation data sources anywhere, no action
# blocks outside allowed_action_types, only allowlisted providers and
# remote-state backends, no provider endpoint, proxy, TLS or inline
# credential (credentials, token_url) overrides, no provider profile,
# credentials-file, static-key, token or impersonation argument outside
# allowed_credential_references, and no reference to an ephemeral type
# outside allowed_ephemeral_types.
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
#   ...resources[i].expressions.config.constant_value.{hostname,token}
#   prior_state...resources[i].values.config.{hostname,token} (read value)
# Blind spots (docs/known-gaps.md):
#   - a `dynamic` block inside a provider block is not rendered in .expressions;
#   - endpoints set through environment variables, an AWS shared config or
#     credentials file (endpoint_url, credential_process) or a google
#     external_account credentials file (token_url) never appear in the plan;
#   - an `ephemeral` block is not rendered: only the references to it are
#     (ephemeral.<type>.<name>), so one that nothing references, or that a
#     local reads, is opened during the plan without this policy seeing it;
#     scripts/check-plan-time-exec.py checks every ephemeral block in CI;
#   - the plan JSON shows the references of a credential argument, not its
#     literals or function calls (the scanner checks those in CI);
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
# this repo sets them. Tokens, profiles, credential files and impersonation
# are in credential_key_pattern, which has an allowlist of reference forms.
endpoint_key_pattern := `^(endpoints?|.*_endpoint|hostname|base_url|api_url|metadata_host|universe_domain|custom_ca_bundle|insecure|ssl_skip_verify|skip_tls_verify|https?_proxy|no_proxy|credentials|token_url)$`

# Provider arguments that pick the identity a provider authenticates as, or
# make it read a file that can run a command (SEC-1). An AWS profile or shared
# config / credentials file can set credential_process (runs a command when
# the provider is configured, at plan and at apply) or endpoint_url; static
# keys and tokens, web-identity token files, google access tokens, external
# credentials and impersonation swap the workspace's identity. Each of these
# is denied unless every reference of its expression is on
# allowed_credential_references for that provider type and argument. No
# provider of this repo sets a credential argument to a literal; a null
# argument (the provider reads its environment) is allowed.
# Not listed: aws assume_role. It runs no code, but it swaps identity: a
# role_arn in an account an attacker controls, whose trust policy admits the
# workspace's role, makes the apply write there (exfiltration), if the
# workspace's identity policy allows sts:AssumeRole on it. The repo's roots
# use a dynamic "assume_role" block, which the plan JSON does not render, and
# the documented stage usage sets a literal ARN, so this policy does not judge
# the role; the TFC roles' identity policies do (docs/known-gaps.md).
credential_key_pattern := `^(profile|shared_config_files|shared_credentials_files|access_key|secret_key|token|access_token|api_token|assume_role_with_web_identity|web_identity_token|web_identity_token_file|impersonate_service_account|impersonate_service_account_delegates|external_credentials)$`

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

# SEC-2 (re-audit 4): a remote-state config with hostname or token sends the
# run's HCP Terraform token to that host during the plan. The configuration
# shows the keys only when config is a constant; the data source's read value
# in prior_state shows them when config holds references. The read has already
# happened when this runs (detective); scripts/check-plan-time-exec.py rejects
# any config key other than organization and workspaces before the plan.
remote_state_forbidden_config_keys := {"hostname", "token"}

deny contains msg if {
	some pair in config_resources
	path := pair[0]
	r := pair[1]
	object.get(r, "mode", "") == "data"
	object.get(r, "type", "") == "terraform_remote_state"
	some k in remote_state_forbidden_config_keys
	object.get(r, ["expressions", "config", "constant_value", k], null) != null
	msg := sprintf("%s: terraform_remote_state config sets %s, which sends the run's token to another host", [full_address(path, r), k])
}

deny contains msg if {
	walk(object.get(input.plan, "prior_state", {}), [_, r])
	is_object(r)
	object.get(r, "mode", "") == "data"
	object.get(r, "type", "") == "terraform_remote_state"
	some k in remote_state_forbidden_config_keys
	object.get(r, ["values", "config", k], null) != null
	msg := sprintf("%s: terraform_remote_state config sets %s, which sends the run's token to another host", [object.get(r, "address", "?"), k])
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

# ── Credential arguments (SEC-1) ───────────────────────────────────────────
# The provider type is the last part of full_name, so a local name that maps
# to another provider gets that provider's allowances only.
provider_type(pc) := t if {
	parts := split(object.get(pc, "full_name", ""), "/")
	t := parts[count(parts) - 1]
}

credential_refs(ptype, attr) := {ref |
	some entry in allowed_credential_references
	parts := split(entry, "=")
	count(parts) == 2
	parts[0] == sprintf("%s/%s", [ptype, attr])
	ref := parts[1]
}

# A reference is allowed when it is exactly an allowed path; [*] in an entry
# matches one literal map key (var.tfc_aws_dynamic_credentials.aliases["backup"]).
ref_pattern(a) := concat("", ["^", replace(replace(a, ".", `\.`), "[*]", `\["[A-Za-z0-9_-]+"\]`), "$"])

ref_allowed(r, allowed) if {
	some a in allowed
	regex.match(ref_pattern(a), r)
}

# A root variable that an allowed expression reads must not bring a value of
# its own: its default is null (HCP Terraform or the workspace sets it) or a
# bool switch. A default holding a file path or an email would otherwise be
# used whenever the workspace does not set the variable.
inert_default(d) if d == null

inert_default(d) if is_boolean(d)

variable_inert(r) if not startswith(r, "var.")

variable_inert(r) if {
	startswith(r, "var.")
	name := ref_variable(r)
	vars := object.get(input.plan.configuration, ["root_module", "variables"], {})
	inert_default(object.get(vars, [name, "default"], null))
	credential_variable_value_ok(name, object.get(input.plan, ["variables", name, "value"], null))
}

ref_variable(r) := substring(regex.find_n(`^var\.[A-Za-z_][A-Za-z0-9_-]*`, r, 1)[0], 4, -1)

# The value the run uses (input.plan.variables), wherever it came from: a
# workspace variable, a committed *.auto.tfvars file or HCP Terraform's
# injection. The plan JSON shows the value as given, without attributes that
# an optional() default would add; the exact reference paths above and the
# scanner's type check cover those.
#
# tfc_aws_dynamic_credentials: null, or {default, aliases} whose
# shared_config_file values are absolute paths. HCP Terraform writes the file
# outside the configuration; its documentation does not give the path, so the
# rule requires an absolute path without "." or ".." segments and outside
# /proc, /dev and /sys (/proc/self/cwd/... would reach the checkout). A
# guessable absolute path into the run's own checkout is not excluded
# (docs/known-gaps.md).
credential_variable_value_ok(_, null)

credential_variable_value_ok("terraform_admin_email", v) if {
	is_string(v)
	regex.match(`^[a-z][a-z0-9-]*@[a-z0-9-]+\.iam\.gserviceaccount\.com$`, v)
}

credential_variable_value_ok("enable_saas_secret_bridge", v) if is_boolean(v)

credential_variable_value_ok("tfc_aws_dynamic_credentials", v) if {
	is_object(v)
	every k, _ in v {
		k in {"default", "aliases"}
	}
	dynamic_config_ok(object.get(v, "default", null))
	every _, c in object.get(v, "aliases", {}) {
		dynamic_config_ok(c)
	}
}

# A variable on allowed_credential_references with no value rule here fails
# closed unless its value is null: add a rule when you add one.

dynamic_config_ok(null)

dynamic_config_ok(c) if {
	is_object(c)
	object.keys(c) == {"shared_config_file"}
	hcp_generated_path(c.shared_config_file)
}

hcp_generated_path(p) if {
	is_string(p)
	regex.match(`^(/[A-Za-z0-9._-]+)+$`, p)
	not regex.match(`/\.\.?(/|$)`, p)
	not regex.match(`^/(proc|dev|sys)(/|$)`, p)
}

# null: the provider reads its environment, as with no argument at all.
credential_ok(_, _, _, expr) if {
	is_object(expr)
	object.keys(expr) == {"constant_value"}
	expr.constant_value == null
}

# Only in the root module (a provider block inside a called module gets no
# allowance), with no constant and only allowed references. The plan JSON
# lists references, not literals or function calls: a literal in a branch of
# a conditional is invisible here and is checked by
# scripts/check-plan-time-exec.py on the repository source.
credential_ok(key, pc, attr, expr) if {
	not contains(key, ":")
	is_object(expr)
	not "constant_value" in object.keys(expr)
	refs := object.get(expr, "references", [])
	count(refs) > 0
	allowed := credential_refs(provider_type(pc), attr)
	every r in refs {
		ref_allowed(r, allowed)
		variable_inert(r)
	}
}

deny contains msg if {
	some key, pc in object.get(input.plan.configuration, "provider_config", {})
	some attr, expr in object.get(pc, "expressions", {})
	regex.match(credential_key_pattern, attr)
	not credential_ok(key, pc, attr, expr)
	msg := sprintf("provider %s sets %q: a profile, credentials file, token or impersonation argument can run a command or swap the workspace's identity; only the exact paths on allowed_credential_references may, and the variables they read need a null or bool default and an allowed value", [key, attr])
}

# ── Ephemeral resources (SEC-2) ────────────────────────────────────────────
# The plan JSON has no entry for an ephemeral block (verified with Terraform
# 1.17.1). Its type shows only in the references of an expression that uses
# it ("ephemeral.<type>.<name>..."), in resources, module calls, outputs and
# provider configurations. An ephemeral block that nothing references, or
# that is read through a local, is invisible here although it is opened (its
# provider code runs) during the plan; scripts/check-plan-time-exec.py
# checks every ephemeral block in the repository (docs/known-gaps.md).
deny contains msg if {
	walk(input.plan.configuration, [path, refs])
	count(path) > 0
	path[count(path) - 1] in {"references", "depends_on"}
	is_array(refs)
	some r in refs
	is_string(r)
	startswith(r, "ephemeral.")
	etype := split(r, ".")[1]
	not etype in allowed_ephemeral_types
	msg := sprintf("ephemeral %q is used: an ephemeral resource runs provider code during the plan and the apply (it can invoke a function or mint a token); only %v may be used", [etype, sort(allowed_ephemeral_types)])
}
