package terraform.policies.aws_iam_no_admin_wildcard_test

import rego.v1

import data.terraform.policies.aws_iam_no_admin_wildcard as p

one(type, after) := {"plan": {"resource_changes": [{
	"address": sprintf("%s.x", [type]),
	"mode": "managed",
	"type": type,
	"change": {"actions": ["create"], "after": after, "after_unknown": {}},
}]}}

doc(stmts) := json.marshal({"Version": "2012-10-17", "Statement": stmts})

test_scoped_policy_passes if {
	count(p.deny) == 0 with input as one("aws_iam_policy", {"policy": doc([{"Effect": "Allow", "Action": ["s3:GetObject"], "Resource": "arn:aws:s3:::b/*"}])})
}

test_admin_policy_fails if {
	count(p.deny) == 1 with input as one("aws_iam_policy", {"policy": doc([{"Effect": "Allow", "Action": "*", "Resource": "*"}])})
}

test_admin_list_form_in_role_policy_fails if {
	count(p.deny) == 1 with input as one("aws_iam_role_policy", {"policy": doc([{"Effect": "Allow", "Action": ["s3:*", "*"], "Resource": ["*"]}])})
}

test_single_statement_object_fails if {
	raw := json.marshal({"Statement": {"Effect": "Allow", "Action": "*", "Resource": "*"}})
	count(p.deny) == 1 with input as one("aws_iam_user_policy", {"policy": raw})
}

test_deny_all_passes if {
	count(p.deny) == 0 with input as one("aws_iam_role_policy", {"policy": doc([{"Effect": "Deny", "Action": "*", "Resource": "*"}])})
}

test_action_star_scoped_resource_passes if {
	count(p.deny) == 0 with input as one("aws_iam_policy", {"policy": doc([{"Effect": "Allow", "Action": "*", "Resource": "arn:aws:s3:::b"}])})
}

test_role_inline_policy_fails if {
	count(p.deny) == 1 with input as one("aws_iam_role", {"inline_policy": [{"name": "i", "policy": doc([{"Effect": "Allow", "Action": "*", "Resource": "*"}])}]})
}

test_unknown_policy_skipped if {
	count(p.deny) == 0 with input as one("aws_iam_policy", {})
}
