# MANDATORY: no provisioners and no external / http data sources outside the
# reviewed allowlist. A plan runs with the workspace's credentials and
# environment variables (TFE_TOKEN, SUPABASE_ACCESS_TOKEN, the cloud plan
# identity): a data "external" or data "http" block runs during the plan and
# can send those values out, and a provisioner (local-exec, remote-exec, file)
# runs arbitrary commands during the apply. scripts/check-consistency.sh
# enforces the same allowlist on the repo; this policy also covers runs whose
# configuration never passed through CI (CLI uploads, another branch).
#
# Allowlist: resources declared directly in a module called with a source
# ending in supabase/vault-secrets (its reviewed bootstrap and reconcile
# provisioners).
package terraform.policies.no_plan_time_code_execution

import rego.v1

exec_data_types := {"external", "http"}

allowed_module_source(src) if regex.match(`(^|/)supabase/vault-secrets/?$`, src)

# Every resource block of the configuration, at any module depth, with its
# walk path: root_module.resources[i] or
# root_module.module_calls.<name>.module(.module_calls.<name>.module)*.resources[i].
config_resources contains [path, r] if {
	walk(input.plan.configuration, [path, r])
	n := count(path)
	n >= 2
	path[n - 2] == "resources"
	is_number(path[n - 1])
	is_object(r)
}

# Source of the module call that declares the resource ("" in the root module).
module_source(path) := src if {
	n := count(path)
	n >= 4
	path[n - 3] == "module"
	call := object.get(input.plan.configuration, array.slice(path, 0, n - 3), {})
	src := object.get(call, "source", "")
} else := ""

exempt(path) if allowed_module_source(module_source(path))

deny contains msg if {
	some pair in config_resources
	path := pair[0]
	r := pair[1]
	some prov in object.get(r, "provisioners", [])
	not exempt(path)
	msg := sprintf("%s: declares a %s provisioner (arbitrary commands at apply time with the workspace's credentials); only modules/supabase/vault-secrets may", [object.get(r, "address", "?"), object.get(prov, "type", "?")])
}

deny contains msg if {
	some pair in config_resources
	path := pair[0]
	r := pair[1]
	object.get(r, "mode", "") == "data"
	object.get(r, "type", "") in exec_data_types
	not exempt(path)
	msg := sprintf("%s: data %q runs at plan time with the workspace's credentials and environment variables; it is not allowed outside modules/supabase/vault-secrets", [object.get(r, "address", "?"), r.type])
}
