# MANDATORY: a role that trusts an OIDC web-identity provider must pin both
# the audience and an exact (or tenant-scoped) subject. A trust with no `sub`
# condition, a bare "*" subject, or a wildcard in the tenant segment
# ("organization:*:...", "repo:*") lets ANY tenant on that issuer assume the
# role: a persistence backdoor (any TFC org / any GitHub repo).
package terraform.policies.aws_iam_federated_trust_pinned

import rego.v1

import data.terraform.lib

federated_web_identity(stmt) if {
	stmt.Effect == "Allow"
	object.get(object.get(stmt, "Principal", {}), "Federated", null) != null
	some action in lib.as_list(object.get(stmt, "Action", null))
	action in {"sts:AssumeRoleWithWebIdentity", "sts:*", "*"}
}

# Condition keys under StringEquals / StringLike (incl. ForAnyValue: forms).
cond_values(stmt, suffix) := [v |
	some op, kv in object.get(stmt, "Condition", {})
	op_matches(op)
	some key, raw in kv
	endswith(key, suffix)
	some v in lib.as_list(raw)
]

op_matches(op) if op in {"StringEquals", "StringLike", "ForAnyValue:StringEquals", "ForAnyValue:StringLike", "ForAllValues:StringEquals", "ForAllValues:StringLike"}

# The tenant segment (first segment after the claim prefix) must be literal:
#   organization:<org>:...   repo:<owner>/<repo>:...   repository_owner_id:<id>:...
open_subject(v) if v == "*"

open_subject(v) if regex.match(`^[A-Za-z_]+:\*`, v)

open_subject(v) if regex.match(`^repo:[^/]*\*[^/]*/`, v)

violation(stmt) := "has no audience (:aud) condition" if {
	count(cond_values(stmt, ":aud")) == 0
}

violation(stmt) := "has no subject (:sub) condition" if {
	count(cond_values(stmt, ":sub")) == 0
}

violation(stmt) := sprintf("has an unpinned subject %q", [v]) if {
	some v in cond_values(stmt, ":sub")
	open_subject(v)
}

deny contains msg if {
	some rc in lib.written_of_type("aws_iam_role")
	raw := lib.after(rc, "assume_role_policy")
	raw != null
	doc := lib.policy_doc(raw)
	some stmt in lib.statements(doc)
	federated_web_identity(stmt)
	reason := violation(stmt)
	msg := sprintf("%s: federated (web-identity) trust %s", [rc.address, reason])
}
