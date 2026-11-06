package terraform.policies.aws_iam_federated_trust_pinned_test

import rego.v1

import data.terraform.policies.aws_iam_federated_trust_pinned as p

role(cond) := {"plan": {"resource_changes": [{
	"address": "aws_iam_role.deploy",
	"mode": "managed",
	"type": "aws_iam_role",
	"change": {"actions": ["create"], "after_unknown": {}, "after": {"assume_role_policy": json.marshal({
		"Version": "2012-10-17",
		"Statement": [{
			"Effect": "Allow",
			"Principal": {"Federated": "arn:aws:iam::111111111111:oidc-provider/app.terraform.io"},
			"Action": "sts:AssumeRoleWithWebIdentity",
			"Condition": cond,
		}],
	})}},
}]}}

test_exact_tfc_subject_passes if {
	count(p.deny) == 0 with input as role({"StringEquals": {
		"app.terraform.io:aud": "aws.workload.identity",
		"app.terraform.io:sub": "organization:acme:project:p:workspace:w:run_phase:apply",
	}})
}

test_org_scoped_like_passes if {
	count(p.deny) == 0 with input as role({
		"StringEquals": {"app.terraform.io:aud": "aws.workload.identity"},
		"StringLike": {"app.terraform.io:sub": "organization:acme:project:p:workspace:*:run_phase:plan"},
	})
}

test_missing_sub_fails if {
	count(p.deny) == 1 with input as role({"StringEquals": {"app.terraform.io:aud": "aws.workload.identity"}})
}

test_missing_aud_fails if {
	count(p.deny) == 1 with input as role({"StringEquals": {"token.actions.githubusercontent.com:sub": "repo:acme/web:ref:refs/heads/main"}})
}

test_wildcard_tenant_fails if {
	count(p.deny) == 1 with input as role({
		"StringEquals": {"app.terraform.io:aud": "aws.workload.identity"},
		"StringLike": {"app.terraform.io:sub": "organization:*:project:p:workspace:w:run_phase:apply"},
	})
}

test_wildcard_github_owner_fails if {
	count(p.deny) == 1 with input as role({
		"StringEquals": {"token.actions.githubusercontent.com:aud": "sts.amazonaws.com"},
		"StringLike": {"token.actions.githubusercontent.com:sub": "repo:*/web:*"},
	})
}

test_service_principal_trust_ignored if {
	inp := {"plan": {"resource_changes": [{
		"address": "aws_iam_role.task",
		"mode": "managed",
		"type": "aws_iam_role",
		"change": {"actions": ["create"], "after_unknown": {}, "after": {"assume_role_policy": json.marshal({"Statement": [{
			"Effect": "Allow",
			"Principal": {"Service": "ecs-tasks.amazonaws.com"},
			"Action": "sts:AssumeRole",
		}]})}},
	}]}}
	count(p.deny) == 0 with input as inp
}

test_partial_wildcard_tenant_fails if {
	count(p.deny) == 1 with input as role({
		"StringEquals": {"app.terraform.io:aud": "aws.workload.identity"},
		"StringLike": {"app.terraform.io:sub": "organization:acme*:project:p:workspace:w:run_phase:apply"},
	})
}

test_unknown_trust_is_advisory if {
	inp := {"plan": {"resource_changes": [{
		"address": "aws_iam_role.deploy",
		"mode": "managed",
		"type": "aws_iam_role",
		"change": {"actions": ["create"], "after": {}, "after_unknown": {"assume_role_policy": true}},
	}]}}
	count(p.deny) == 0 with input as inp
	count(p.federated_unknown) == 1 with input as inp
}
