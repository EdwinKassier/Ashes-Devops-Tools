package terraform.policies.gcp_iam_no_public_members_test

import rego.v1

import data.terraform.policies.gcp_iam_no_public_members as p

one(type, after) := {"plan": {"resource_changes": [{
	"address": sprintf("%s.x", [type]),
	"mode": "managed",
	"type": type,
	"change": {"actions": ["create"], "after": after, "after_unknown": {}},
}]}}

test_private_member_passes if {
	count(p.deny) == 0 with input as one("google_storage_bucket_iam_member", {"role": "roles/storage.objectViewer", "member": "group:eng@example.com"})
}

test_all_users_member_fails if {
	count(p.deny) == 1 with input as one("google_cloud_run_v2_service_iam_member", {"role": "roles/run.invoker", "member": "allUsers"})
}

test_all_authenticated_binding_fails if {
	count(p.deny) == 1 with input as one("google_project_iam_binding", {"role": "roles/viewer", "members": ["user:a@example.com", "allAuthenticatedUsers"]})
}

test_policy_data_public_fails if {
	doc := json.marshal({"bindings": [{"role": "roles/viewer", "members": ["allUsers"]}]})
	count(p.deny) == 1 with input as one("google_pubsub_topic_iam_policy", {"policy_data": doc})
}

test_policy_data_private_passes if {
	doc := json.marshal({"bindings": [{"role": "roles/viewer", "members": ["group:a@example.com"]}]})
	count(p.deny) == 0 with input as one("google_pubsub_topic_iam_policy", {"policy_data": doc})
}

test_non_iam_type_ignored if {
	count(p.deny) == 0 with input as one("google_project_service", {"member": "allUsers"})
}
