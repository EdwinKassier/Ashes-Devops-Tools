# MANDATORY: no identity-based IAM policy may Allow Action "*" on Resource "*"
# (full administrator). Deny statements with "*" are fine (break-glass
# standing deny-all). Managed AdministratorAccess attachments are a separate,
# reviewed decision and are not covered here.
package terraform.policies.aws_iam_no_admin_wildcard

import rego.v1

import data.terraform.lib

# Resource types whose `policy` attribute is an identity policy JSON document.
policy_types := {
	"aws_iam_policy",
	"aws_iam_role_policy",
	"aws_iam_user_policy",
	"aws_iam_group_policy",
}

# (address, raw policy JSON) pairs to inspect.
documents contains [rc.address, lib.after(rc, "policy")] if {
	some t in policy_types
	some rc in lib.written_of_type(t)
	lib.after(rc, "policy") != null
}

# Legacy aws_iam_role inline_policy blocks.
documents contains [rc.address, block.policy] if {
	some rc in lib.written_of_type("aws_iam_role")
	some block in object.get(rc.change.after, "inline_policy", [])
	is_string(block.policy)
	block.policy != ""
}

admin_statement(stmt) if {
	stmt.Effect == "Allow"
	"*" in lib.as_list(object.get(stmt, "Action", null))
	"*" in lib.as_list(object.get(stmt, "Resource", null))
}

deny contains msg if {
	some [address, raw] in documents
	doc := lib.policy_doc(raw)
	some stmt in lib.statements(doc)
	admin_statement(stmt)
	msg := sprintf("%s: policy Allows Action \"*\" on Resource \"*\"", [address])
}
