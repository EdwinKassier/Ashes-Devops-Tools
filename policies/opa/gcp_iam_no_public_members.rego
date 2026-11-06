# MANDATORY: no GCP IAM grant to allUsers / allAuthenticatedUsers on ANY
# resource (google_*_iam_member, google_*_iam_binding, google_*_iam_policy).
# Domain-restricted sharing (iam.allowedPolicyMemberDomains) blocks this at
# the org; this policy catches it at plan time, before the API rejects it.
package terraform.policies.gcp_iam_no_public_members

import rego.v1

import data.terraform.lib

public_members := {"allUsers", "allAuthenticatedUsers"}

iam_member_or_binding(t) if regex.match(`^google_[a-z0-9_]+_iam_(member|binding)$`, t)

iam_policy(t) if regex.match(`^google_[a-z0-9_]+_iam_policy$`, t)

# iam_binding carries members (list); iam_member a single member string.
members(rc) := rc.change.after.members if is_array(rc.change.after.members)

members(rc) := [rc.change.after.member] if is_string(rc.change.after.member)

# iam_policy carries policy_data: a JSON {bindings = [{role, members}]}.
members(rc) := [m |
	doc := lib.policy_doc(rc.change.after.policy_data)
	some binding in object.get(doc, "bindings", [])
	some m in object.get(binding, "members", [])
] if {
	iam_policy(rc.type)
}

deny contains msg if {
	some rc in lib.managed
	iam_member_or_binding(rc.type)
	lib.writes(rc)
	some member in members(rc)
	member in public_members
	msg := sprintf("%s: grants %s to public principal %s", [rc.address, rc.change.after.role, member])
}

deny contains msg if {
	some rc in lib.managed
	iam_policy(rc.type)
	lib.writes(rc)
	some member in members(rc)
	member in public_members
	msg := sprintf("%s: policy_data grants access to public principal %s", [rc.address, member])
}
