package terraform.policies.gcp_no_basic_roles_high_scope_test

import rego.v1

import data.terraform.policies.gcp_no_basic_roles_high_scope as p

grant(type, role) := {"plan": {"resource_changes": [{
	"address": sprintf("%s.x", [type]),
	"mode": "managed",
	"type": type,
	"change": {"actions": ["create"], "after_unknown": {}, "after": {"role": role, "member": "group:g@acme.io"}},
}]}}

test_org_owner_fails if {
	count(p.deny) == 1 with input as grant("google_organization_iam_member", "roles/owner")
}

test_folder_editor_binding_fails if {
	count(p.deny) == 1 with input as grant("google_folder_iam_binding", "roles/editor")
}

test_predefined_role_passes if {
	count(p.deny) == 0 with input as grant("google_organization_iam_member", "roles/resourcemanager.folderViewer")
}

test_project_owner_not_in_scope if {
	count(p.deny) == 0 with input as grant("google_project_iam_member", "roles/owner")
}

test_authoritative_policy_fails if {
	inp := {"plan": {"resource_changes": [{
		"address": "google_folder_iam_policy.x",
		"mode": "managed",
		"type": "google_folder_iam_policy",
		"change": {"actions": ["update"], "after_unknown": {}, "after": {"policy_data": json.marshal({"bindings": [{"role": "roles/owner", "members": ["user:a@acme.io"]}]})}},
	}]}}
	count(p.deny) == 1 with input as inp
}
