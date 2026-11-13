package terraform.policies.aws_iam_federated_trust_pinned_test

import rego.v1

import data.terraform.policies.aws_iam_federated_trust_pinned as p

role(cond) := role_stmt("sts:AssumeRoleWithWebIdentity", cond)

role_stmt(action, cond) := role_doc({
	"Effect": "Allow",
	"Principal": {"Federated": "arn:aws:iam::111111111111:oidc-provider/app.terraform.io"},
	"Action": action,
	"Condition": cond,
})

role_doc(stmt) := {"plan": {"resource_changes": [{
	"address": "aws_iam_role.deploy",
	"mode": "managed",
	"type": "aws_iam_role",
	"change": {"actions": ["create"], "after_unknown": {}, "after": {"assume_role_policy": json.marshal({
		"Version": "2012-10-17",
		"Statement": [stmt],
	})}},
}]}}

test_exact_tfc_subject_passes if {
	count(p.deny) == 0 with input as role({"StringEquals": {
		"app.terraform.io:aud": "aws.workload.identity",
		"app.terraform.io:sub": "organization:acme:project:p:workspace:w:run_phase:apply",
	}})
}

# A workspace wildcard trusts every workspace of the project, including one a
# project member creates: the workspace segment must be literal too.
test_workspace_wildcard_denied if {
	count(p.deny) == 1 with input as role({
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

# ── Bypasses found by the 2026-11-13 re-audit (SEC-1) ───────────────────────
tfc_aud := {"app.terraform.io:aud": "aws.workload.identity"}

gh_aud := {"token.actions.githubusercontent.com:aud": "sts.amazonaws.com"}

tfc_like(sub) := role({"StringEquals": tfc_aud, "StringLike": {"app.terraform.io:sub": sub}})

gh_like(sub) := role({"StringEquals": gh_aud, "StringLike": {"token.actions.githubusercontent.com:sub": sub}})

gh_exact(sub) := role({"StringEquals": object.union(gh_aud, {"token.actions.githubusercontent.com:sub": sub})})

# A literal organization followed by wildcards trusts every project,
# workspace and run phase of the organization.
test_tfc_wildcards_after_org_denied if {
	count(p.deny) == 1 with input as tfc_like("organization:acme:project:*:workspace:*:run_phase:*")
}

test_tfc_project_wildcard_denied if {
	count(p.deny) == 1 with input as tfc_like("organization:acme:project:*:workspace:w:run_phase:apply")
}

# A plan-phase token must not reach an apply role.
test_tfc_run_phase_wildcard_denied if {
	count(p.deny) == 1 with input as tfc_like("organization:acme:project:p:workspace:w:run_phase:*")
}

test_tfc_single_char_wildcard_denied if {
	count(p.deny) == 1 with input as tfc_like("organization:acme:project:p:workspace:w?:run_phase:apply")
}

# Missing segments: the subject does not name a workspace and a run phase.
test_tfc_short_subject_denied if {
	count(p.deny) == 1 with input as role({"StringEquals": object.union(tfc_aud, {"app.terraform.io:sub": "organization:acme:project:p"})})
}

test_tfc_unknown_run_phase_denied if {
	count(p.deny) == 1 with input as role({"StringEquals": object.union(tfc_aud, {"app.terraform.io:sub": "organization:acme:project:p:workspace:w:run_phase:any"})})
}

# An action pattern that matches sts:AssumeRoleWithWebIdentity is federated.
test_action_glob_is_federated if {
	count(p.deny) == 2 with input as role_stmt("sts:AssumeRoleWith*", {})
}

test_action_glob_in_list_is_federated if {
	count(p.deny) == 1 with input as role_stmt(["sts:TagSession", "sts:AssumeRole*"], {"StringEquals": tfc_aud})
}

test_action_glob_question_mark_is_federated if {
	count(p.deny) == 1 with input as role_stmt("sts:AssumeRoleWith?ebIdentity", {"StringEquals": tfc_aud})
}

# IAM action names are case-insensitive.
test_action_other_case_is_federated if {
	count(p.deny) == 1 with input as role_stmt("STS:assumerolewithwebidentity", {"StringEquals": tfc_aud})
}

# NotAction allows every action it does not list, web identity included.
test_not_action_is_federated if {
	count(p.deny) == 1 with input as role_doc({
		"Effect": "Allow",
		"Principal": {"Federated": "arn:aws:iam::111111111111:oidc-provider/app.terraform.io"},
		"NotAction": "sts:AssumeRole",
		"Condition": {"StringEquals": tfc_aud},
	})
}

test_not_action_listing_web_identity_ignored if {
	count(p.deny) == 0 with input as role_doc({
		"Effect": "Allow",
		"Principal": {"Federated": "arn:aws:iam::111111111111:oidc-provider/app.terraform.io"},
		"NotAction": "sts:AssumeRoleWithWebIdentity",
	})
}

# A SAML provider cannot issue a web-identity token: the glob is not federated web identity.
test_saml_provider_glob_ignored if {
	count(p.deny) == 0 with input as role_doc({
		"Effect": "Allow",
		"Principal": {"Federated": "arn:aws:iam::111111111111:saml-provider/okta"},
		"Action": "sts:AssumeRoleWith*",
		"Condition": {"StringEquals": {"SAML:aud": "https://signin.aws.amazon.com/saml"}},
	})
}

test_saml_and_oidc_provider_glob_federated if {
	count(p.deny) == 1 with input as role_doc({
		"Effect": "Allow",
		"Principal": {"Federated": ["arn:aws:iam::111111111111:saml-provider/okta", "arn:aws:iam::111111111111:oidc-provider/app.terraform.io"]},
		"Action": "sts:AssumeRoleWith*",
		"Condition": {"StringEquals": tfc_aud},
	})
}

# GitHub: a literal repository with any context trusts every branch, tag,
# pull request and environment of it.
test_github_any_context_denied if count(p.deny) == 1 with input as gh_like("repo:acme/app:*")

test_github_ref_wildcard_denied if count(p.deny) == 1 with input as gh_like("repo:acme/app:ref:refs/heads/*")

test_github_pull_request_denied if count(p.deny) == 1 with input as gh_exact("repo:acme/app:pull_request")

test_github_repo_only_id_template_denied if count(p.deny) == 1 with input as gh_exact("repository_owner_id:1:repository_id:2")

test_github_owner_only_id_template_denied if count(p.deny) == 1 with input as gh_exact("repository_owner_id:1:environment:prod")

# A wildcard is denied on any issuer, not only TFC and GitHub.
test_other_issuer_wildcard_denied if {
	count(p.deny) == 1 with input as role({"StringEquals": {"oidc.example.com:aud": "sts"}, "StringLike": {"oidc.example.com:sub": "system:serviceaccount:apps:*"}})
}

# ── Allowed: every trust document the repository builds ─────────────────────
# modules/aws/iam/tfc-management-roles and tfc-oidc-baseline (StringEquals,
# one exact subject); a TFC project name may hold spaces.
test_repo_tfc_management_role_passes if {
	count(p.deny) == 0 with input as role({"StringEquals": object.union(tfc_aud, {"app.terraform.io:sub": "organization:acme:project:Landing Zone:workspace:aws-security:run_phase:apply"})})
}

# templates/aws/bootstrap/phase0-management.yaml: a list of exact subjects.
test_repo_phase0_subject_list_passes if {
	count(p.deny) == 0 with input as role({"StringEquals": object.union(tfc_aud, {"app.terraform.io:sub": [
		"organization:acme:project:acme-aws:workspace:aws-organization:run_phase:plan",
		"organization:acme:project:acme-aws:workspace:aws-security:run_phase:plan",
		"organization:acme:project:acme-aws:workspace:aws-backup:run_phase:plan",
	]})})
}

test_repo_phase0_subject_list_with_one_wildcard_denied if {
	count(p.deny) == 1 with input as role({"StringEquals": tfc_aud, "StringLike": {"app.terraform.io:sub": [
		"organization:acme:project:acme-aws:workspace:aws-organization:run_phase:apply",
		"organization:acme:project:acme-aws:workspace:*:run_phase:apply",
	]}})
}

# modules/aws/stages/app-services GitHub deploy roles: name-based and
# ID-based subjects, with a ref or an environment.
test_repo_github_name_environment_passes if count(p.deny) == 0 with input as gh_exact("repo:acme/web:environment:prod")

test_repo_github_name_ref_passes if count(p.deny) == 0 with input as gh_exact("repo:acme/web:ref:refs/heads/main")

test_repo_github_id_environment_passes if count(p.deny) == 0 with input as gh_exact("repository_owner_id:111:repository_id:222:environment:prod")

test_repo_github_id_ref_passes if count(p.deny) == 0 with input as gh_exact("repository_owner_id:111:repository_id:222:ref:refs/heads/main")

# ── Unknown trust documents ─────────────────────────────────────────────────
unknown_role := {
	"address": "aws_iam_role.deploy",
	"mode": "managed",
	"type": "aws_iam_role",
	"change": {"actions": ["create"], "after": {}, "after_unknown": {"assume_role_policy": true}},
}

created(type) := {
	"address": sprintf("%s.this", [type]),
	"mode": "managed",
	"type": type,
	"change": {"actions": ["create"], "after": {}, "after_unknown": {}},
}

# Nothing in the run explains the unknown trust: it cannot be checked, so it
# is denied (a wildcard subject could hide behind any apply-time value).
test_unknown_trust_denied if {
	inp := {"plan": {"resource_changes": [unknown_role]}}
	count(p.deny) == 1 with input as inp
	count(p.federated_unknown) == 1 with input as inp
}

test_unknown_trust_on_update_denied if {
	rc := json.patch(unknown_role, [{"op": "replace", "path": "/change/actions", "value": ["update"]}])
	count(p.deny) == 1 with input as {"plan": {"resource_changes": [rc]}}
}

# An existing OIDC provider (no create) does not excuse an unknown trust.
test_unknown_trust_with_existing_provider_denied if {
	provider := json.patch(created("aws_iam_openid_connect_provider"), [{"op": "replace", "path": "/change/actions", "value": ["no-op"]}])
	count(p.deny) == 1 with input as {"plan": {"resource_changes": [unknown_role, provider]}}
}

# First apply of a GitHub deploy role in modules/aws/stages/app-services: the
# trust names an OIDC provider created in the same run, so it is unknown until
# apply. Denying it would block that run, so it stays advisory.
test_unknown_trust_with_new_oidc_provider_is_advisory if {
	inp := {"plan": {"resource_changes": [unknown_role, created("aws_iam_openid_connect_provider")]}}
	count(p.deny) == 0 with input as inp
	count(p.federated_unknown) == 1 with input as inp
}

# Greenfield aws-organization: the guard-alert forwarder and trail delivery
# roles condition on the management account ID of the organization created in
# the same run.
test_unknown_trust_with_new_organization_is_advisory if {
	inp := {"plan": {"resource_changes": [unknown_role, created("aws_organizations_organization")]}}
	count(p.deny) == 0 with input as inp
	count(p.federated_unknown) == 1 with input as inp
}
