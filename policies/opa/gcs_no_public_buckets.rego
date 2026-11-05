# Advisory: no Cloud Storage bucket may be publicly reachable.
#   - google_storage_bucket must set public_access_prevention = "enforced".
#   - no bucket IAM grant to allUsers / allAuthenticatedUsers.
# Input is the HCP Terraform OPA document; input.plan is the JSON plan.
package terraform.policies.gcs_no_public_buckets

import rego.v1

import input.plan as plan

public_members := {"allUsers", "allAuthenticatedUsers"}

bucket_iam_types := {
	"google_storage_bucket_iam_member",
	"google_storage_bucket_iam_binding",
}

writes(rc) if {
	some action in rc.change.actions
	action in {"create", "update"}
}

deny contains msg if {
	some rc in plan.resource_changes
	rc.type == "google_storage_bucket"
	writes(rc)
	rc.change.after.public_access_prevention != "enforced"
	msg := sprintf("%s: public_access_prevention must be \"enforced\"", [rc.address])
}

deny contains msg if {
	some rc in plan.resource_changes
	rc.type in bucket_iam_types
	writes(rc)
	some member in members(rc.change.after)
	member in public_members
	msg := sprintf("%s: grants bucket access to public principal %s", [rc.address, member])
}

# iam_binding carries a members list; iam_member a single member string.
members(after) := after.members if is_array(after.members)

members(after) := [after.member] if {
	not is_array(after.members)
	is_string(after.member)
}
