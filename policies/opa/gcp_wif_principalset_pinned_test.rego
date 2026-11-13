package terraform.policies.gcp_wif_principalset_pinned_test

import rego.v1

import data.terraform.policies.gcp_wif_principalset_pinned as p

pool := "principalSet://iam.googleapis.com/projects/2/locations/global/workloadIdentityPools/apps-prod"

rc_with(type, actions, after, after_unknown) := {"plan": {"resource_changes": [{
	"address": sprintf("%s.x", [type]),
	"mode": "managed",
	"type": type,
	"change": {"actions": actions, "after": after, "after_unknown": after_unknown},
}]}}

one(type, after) := rc_with(type, ["create"], after, {})

sa_member(m) := one("google_service_account_iam_member", {"role": "roles/iam.workloadIdentityUser", "member": m})

member_of(suffix) := sprintf("%s/%s", [pool, suffix])

# ── Mandatory: too-wide principalSets are denied ────────────────────────────
test_whole_pool_denied if count(p.deny) == 1 with input as sa_member(member_of("*"))

test_owner_wide_denied if count(p.deny) == 1 with input as sa_member(member_of("attribute.repository_owner_id/42"))

test_repository_name_denied if count(p.deny) == 1 with input as sa_member(member_of("attribute.repository/acme/api"))

test_ref_only_denied if count(p.deny) == 1 with input as sa_member(member_of("attribute.ref/refs/heads/main"))

test_binding_list_denied if {
	count(p.deny) == 1 with input as one("google_service_account_iam_binding", {"role": "roles/iam.workloadIdentityUser", "members": ["group:a@acme.io", member_of("*")]})
}

test_policy_data_denied if {
	doc := json.marshal({"bindings": [{"role": "roles/iam.workloadIdentityUser", "members": [member_of("*")]}]})
	count(p.deny) == 1 with input as one("google_service_account_iam_policy", {"policy_data": doc})
}

# Direct resource access: a principalSet granted a role on a project is just
# as wide as one that impersonates a service account.
test_project_role_whole_pool_denied if {
	count(p.deny) == 1 with input as one("google_project_iam_member", {"role": "roles/run.developer", "member": member_of("*")})
}

test_update_denied if {
	count(p.deny) == 1 with input as rc_with("google_service_account_iam_member", ["update"], {"role": "roles/iam.workloadIdentityUser", "member": member_of("*")}, {})
}

# A binding list whose other elements are unknown still has its known
# too-wide member checked.
test_binding_partly_unknown_known_member_denied if {
	count(p.deny) == 1 with input as rc_with(
		"google_service_account_iam_binding", ["create"],
		{"role": "roles/iam.workloadIdentityUser", "members": [null, member_of("*")]},
		{"members": [true, false]},
	)
}

# ── Mandatory: pinned members pass ──────────────────────────────────────────
test_repo_env_pin_passes if count(p.deny) == 0 with input as sa_member(member_of("attribute.repo_env/123/prod"))

test_repo_ref_env_pin_passes if count(p.deny) == 0 with input as sa_member(member_of("attribute.repo_ref_env/123/refs/heads/main/prod"))

test_repo_ref_pin_passes if count(p.deny) == 0 with input as sa_member(member_of("attribute.repo_ref/123/refs/heads/main"))

test_tfc_workspace_phase_passes if count(p.deny) == 0 with input as sa_member(member_of("attribute.workspace_id_phase/ws-abc:apply"))

test_service_account_member_passes if count(p.deny) == 0 with input as sa_member("serviceAccount:ci@p.iam.gserviceaccount.com")

test_workforce_group_principalset_passes if {
	count(p.deny) == 0 with input as one("google_project_iam_member", {"role": "roles/viewer", "member": "principalSet://goog/group/eng@acme.io"})
}

test_delete_ignored if {
	count(p.deny) == 0 with input as rc_with("google_service_account_iam_member", ["delete"], null, {})
}

test_non_iam_type_ignored if {
	count(p.deny) == 0 with input as one("google_iam_workload_identity_pool", {"member": member_of("*")})
}

# ── Advisory: repository-wide and unknown members ───────────────────────────
test_repository_id_only_is_advisory if {
	inp := sa_member(member_of("attribute.repository_id/123"))
	count(p.deny) == 0 with input as inp
	count(p.repo_wide) == 1 with input as inp
}

test_pinned_member_not_advisory if {
	count(p.repo_wide) == 0 with input as sa_member(member_of("attribute.repo_env/123/prod"))
}

test_unknown_member_is_advisory if {
	inp := rc_with("google_service_account_iam_member", ["create"], {"role": "roles/iam.workloadIdentityUser"}, {"member": true})
	count(p.deny) == 0 with input as inp
	count(p.repo_wide) == 1 with input as inp
}

test_unknown_binding_members_is_advisory if {
	inp := rc_with("google_service_account_iam_binding", ["create"], {"role": "roles/iam.workloadIdentityUser", "members": [null]}, {"members": [true]})
	count(p.deny) == 0 with input as inp
	count(p.repo_wide) == 1 with input as inp
}

test_unknown_policy_data_is_advisory if {
	inp := rc_with("google_service_account_iam_policy", ["create"], {}, {"policy_data": true})
	count(p.deny) == 0 with input as inp
	count(p.repo_wide) == 1 with input as inp
}

# An unknown member on a role that cannot federate (an SA email created in
# the same run, say) is not WIF and is not reported.
test_unknown_member_other_role_not_advisory if {
	count(p.repo_wide) == 0 with input as rc_with("google_project_iam_member", ["create"], {"role": "roles/logging.logWriter"}, {"member": true})
}

# ── Bypasses found by the 2026-11-13 re-audit (SEC-1) ───────────────────────
# Raw TFC claims trust every workspace of every organization on the issuer
# (run phase), or a mutable workspace name in any organization.
test_tfc_run_phase_denied if count(p.deny) == 1 with input as sa_member(member_of("attribute.terraform_run_phase/apply"))

test_tfc_workspace_name_denied if count(p.deny) == 1 with input as sa_member(member_of("attribute.terraform_workspace_name/gcp-organization"))

test_tfc_workspace_id_only_denied if count(p.deny) == 1 with input as sa_member(member_of("attribute.terraform_workspace_id/ws-abc"))

test_tfc_organization_denied if count(p.deny) == 1 with input as sa_member(member_of("attribute.terraform_organization_name/acme"))

test_tfc_raw_claim_on_project_role_denied if {
	count(p.deny) == 1 with input as one("google_project_iam_member", {"role": "roles/storage.admin", "member": member_of("attribute.terraform_project_id/prj-abc")})
}

# The GitHub owner name, the actor and the audience trust more than one repository.
test_owner_name_denied if count(p.deny) == 1 with input as sa_member(member_of("attribute.repository_owner/acme"))

test_actor_denied if count(p.deny) == 1 with input as sa_member(member_of("attribute.actor/octocat"))

test_aud_denied if count(p.deny) == 1 with input as sa_member(member_of("attribute.aud/gcp.workload.identity"))

# Workforce identities (people) must not federate into a service account.
workforce := "principalSet://iam.googleapis.com/locations/global/workforcePools/staff"

test_workforce_pool_impersonation_denied if count(p.deny) == 1 with input as sa_member(sprintf("%s/*", [workforce]))

test_workforce_group_impersonation_denied if count(p.deny) == 1 with input as sa_member(sprintf("%s/group/eng", [workforce]))

test_workforce_subject_token_creator_denied if {
	count(p.deny) == 1 with input as one("google_service_account_iam_member", {"role": "roles/iam.serviceAccountTokenCreator", "member": "principal://iam.googleapis.com/locations/global/workforcePools/staff/subject/alice"})
}

test_workforce_in_policy_data_denied if {
	doc := json.marshal({"bindings": [{"role": "roles/iam.workloadIdentityUser", "members": [sprintf("%s/*", [workforce])]}]})
	count(p.deny) == 1 with input as one("google_service_account_iam_policy", {"policy_data": doc})
}

test_workforce_unknown_role_denied if {
	count(p.deny) == 1 with input as rc_with("google_service_account_iam_member", ["create"], {"member": sprintf("%s/*", [workforce])}, {"role": true})
}

# A workforce group on a non-federating role is ordinary access, not impersonation.
test_workforce_group_viewer_passes if {
	count(p.deny) == 0 with input as one("google_project_iam_member", {"role": "roles/viewer", "member": sprintf("%s/group/eng", [workforce])})
}

test_workforce_in_policy_data_other_role_passes if {
	doc := json.marshal({"bindings": [{"role": "roles/viewer", "members": [sprintf("%s/*", [workforce])]}]})
	count(p.deny) == 0 with input as one("google_project_iam_policy", {"policy_data": doc})
}

# ── Allowed: every binding the repository builds ────────────────────────────
# modules/gcp/iam/workload-identity TFC bindings (gcp-bootstrap): workspace ID
# + phase, or workspace name + phase when no ID is configured.
test_repo_tfc_workspace_name_phase_passes if count(p.deny) == 0 with input as sa_member(member_of("attribute.workspace_phase/gcp-organization:plan"))

test_repo_tfc_workspace_id_phase_apply_passes if count(p.deny) == 0 with input as sa_member(member_of("attribute.workspace_id_phase/ws-AbC123:apply"))

# modules/gcp/stages/app-services deploy bindings and workload-identity GitHub bindings.
test_repo_app_deploy_repo_ref_env_passes if {
	count(p.deny) == 0 with input as one("google_service_account_iam_member", {"role": "roles/iam.workloadIdentityUser", "member": member_of("attribute.repo_ref_env/222/refs/heads/main/prod")})
}

# workload-identity GitLab bindings (project_path) are out of scope and pass.
test_repo_gitlab_project_path_passes if count(p.deny) == 0 with input as sa_member(member_of("attribute.project_path/acme/app"))
