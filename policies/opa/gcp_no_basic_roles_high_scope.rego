# MANDATORY: no basic role (Owner / Editor) at organization or folder scope.
# They grant every permission on every project below, cannot be bounded by IAM
# conditions in a meaningful way, and bypass the per-stage least-privilege SA
# design. Use predefined or custom roles instead.
package terraform.policies.gcp_no_basic_roles_high_scope

import rego.v1

import data.terraform.lib

basic_roles := {"roles/owner", "roles/editor"}

iam_types := {
	"google_organization_iam_member",
	"google_organization_iam_binding",
	"google_folder_iam_member",
	"google_folder_iam_binding",
}

deny contains msg if {
	some t in iam_types
	some rc in lib.written_of_type(t)
	role := lib.after(rc, "role")
	role in basic_roles
	msg := sprintf("%s: basic role %s granted at %s scope", [rc.address, role, scope(t)])
}

# Authoritative policies (google_*_iam_policy) carry the bindings in policy_data.
deny contains msg if {
	some t in {"google_organization_iam_policy", "google_folder_iam_policy"}
	some rc in lib.written_of_type(t)
	raw := lib.after(rc, "policy_data")
	is_string(raw)
	some b in object.get(json.unmarshal(raw), "bindings", [])
	b.role in basic_roles
	msg := sprintf("%s: basic role %s granted at %s scope", [rc.address, b.role, scope(t)])
}

scope(t) := "organization" if startswith(t, "google_organization")

scope(t) := "folder" if startswith(t, "google_folder")
