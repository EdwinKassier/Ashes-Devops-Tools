# MANDATORY (deny) + ADVISORY (repo_wide): a workload identity principalSet
# must pin one repository AND a ref or an environment. The GitHub provider
# condition pins only the owner (custom.wifProviderTenantPinned), so a
# principalSet on the whole pool (/*), on the owner, on a mutable repository
# name, on an actor or on a bare ref trusts every repository of the owner.
# A raw Terraform Cloud claim (attribute.terraform_*) or the audience trusts
# every workspace, run phase or organization that shares it: TFC bindings use
# the composite attribute.workspace_id_phase (or workspace_phase) instead. The
# deny covers every google_*_iam_member, google_*_iam_binding and
# google_*_iam_policy, for any role: service account impersonation and direct
# resource access alike.
#
# On every role, a principalSet under a workload pool must be one of the
# pinned forms the repo builds (allowlist): attribute.repo_ref, repo_env (with
# an environment), repo_ref_env, workspace_id_phase or workspace_phase, with
# no `*` or `?`. attribute.repository_id and attribute.project_path pass with
# an advisory (repo_wide). Every other attribute, group or form is denied:
# roles such as serviceAccountUser, serviceAccountAdmin or a custom role can
# reach a service account too. The scheme, host and pool path of a member are
# matched without case.
#
# A principal://.../subject/<sub> member is denied, on any role, when <sub> is
# a TFC or GitHub subject that aws_iam_federated_trust_pinned would deny
# (shared rules in lib_helpers.rego).
#
# Workforce identities (people from an external IdP) must not hold a role
# through which a principal acts as a service account: a workforce pool member
# (principal:// or principalSet://) on a federating, unknown or custom role is
# denied.
#
# Unknown values: a member that embeds a pool created in the same run (the
# pool name holds the project number) is unknown at plan time and cannot be
# required known without blocking the run that creates the pool. Such members
# are not denied; the advisory rule reports them when the role can federate.
package terraform.policies.gcp_wif_principalset_pinned

import rego.v1

import data.terraform.lib

pool_prefix := `^(?i:principalSet://iam\.googleapis\.com/projects/[^/]+/locations/global/workloadIdentityPools/)[^/]+/`

# Suffixes after the pool prefix that trust more than one repository + ref or
# environment: the whole pool, the owner (ID or name), a repository name
# (mutable, and every branch of it), an actor (every repository the person can
# run in), a bare ref (that ref in every repository), the audience and any raw
# Terraform Cloud claim (every workspace or run phase that shares it), an AWS
# account (every role in it) and repo_env without an environment.
too_wide_patterns := [
	`\*$`,
	`attribute\.repository_owner_id/`,
	`attribute\.repository_owner/`,
	`attribute\.repository/`,
	`attribute\.actor/`,
	`attribute\.ref/`,
	`attribute\.aud/`,
	`attribute\.terraform_[a-z0-9_]+/`,
	`attribute\.account/`,
	`attribute\.repo_env/[^/]+/-$`,
	`.*[*?]`,
]

# Pinned forms a federating principalSet may take (suffix after the pool).
pinned_patterns := [
	`attribute\.repo_ref/[^/]+/.+$`,
	`attribute\.repo_env/[^/]+/[^/]+$`,
	`attribute\.repo_ref_env/[^/]+/.+/[^/]+$`,
	`attribute\.workspace_id_phase/[^/:]+:(plan|apply)$`,
	`attribute\.workspace_phase/[^/:]+:(plan|apply)$`,
]

# Forms that pass with an advisory: every branch of one repository, or every
# ref of one GitLab project.
advisory_patterns := [
	`attribute\.repository_id/[^/]+$`,
	`attribute\.project_path/.+$`,
]

pool_member(m) if regex.match(pool_prefix, m)

matches_any(m, patterns) if {
	some pat in patterns
	regex.match(concat("", [pool_prefix, pat]), m)
}

pinned(m) if {
	matches_any(m, pinned_patterns)
	not too_wide(m)
}

subject_prefix := `^(?i:principal://iam\.googleapis\.com/projects/[^/]+/locations/global/workloadIdentityPools/)[^/]+/(?i:subject)/`

# A workload pool subject that the AWS federated-trust policy would deny.
unpinned_subject(m) if {
	regex.match(subject_prefix, m)
	sub := regex.replace(m, subject_prefix, "")
	startswith(sub, "organization:")
	not lib.tfc_subject_pinned(sub)
}

unpinned_subject(m) if {
	regex.match(subject_prefix, m)
	sub := regex.replace(m, subject_prefix, "")
	lib.github_subject_shape(sub)
	not lib.github_subject_pinned(sub)
}

workforce_member(m) if regex.match(`^(?i:principal(Set)?://iam\.googleapis\.com/locations/global/workforcePools/)`, m)

# Roles through which a federated principal acts as a service account.
federating_roles := {
	"roles/iam.workloadIdentityUser",
	"roles/iam.serviceAccountTokenCreator",
	"roles/iam.serviceAccountOpenIdTokenCreator",
	"roles/iam.serviceAccountKeyAdmin",
}

iam_member_or_binding(t) if regex.match(`^google_[a-z0-9_]+_iam_(member|binding)$`, t)

iam_policy(t) if regex.match(`^google_[a-z0-9_]+_iam_policy$`, t)

# Known member strings only; unknown list elements render as null.
members(rc) := [m | some m in rc.change.after.members; is_string(m)] if {
	iam_member_or_binding(rc.type)
	is_array(rc.change.after.members)
}

members(rc) := [rc.change.after.member] if {
	iam_member_or_binding(rc.type)
	is_string(rc.change.after.member)
}

members(rc) := [m |
	doc := lib.policy_doc(rc.change.after.policy_data)
	some binding in object.get(doc, "bindings", [])
	some m in object.get(binding, "members", [])
	is_string(m)
] if iam_policy(rc.type)

# [role, member] pairs with known member strings; role is null when unknown.
role_members(rc) := [[lib.after(rc, "role"), m] | some m in members(rc)] if not iam_policy(rc.type)

role_members(rc) := [[object.get(binding, "role", null), m] |
	doc := lib.policy_doc(rc.change.after.policy_data)
	some binding in object.get(doc, "bindings", [])
	some m in object.get(binding, "members", [])
	is_string(m)
] if iam_policy(rc.type)

# A federating role, or a role that is unknown at plan time (fail closed).
federating_or_unknown_role(_, role) if role in federating_roles

federating_or_unknown_role(rc, _) if lib.unknown(rc, "role")

# Workforce rule: a custom role may hold impersonation permissions too.
workforce_risky_role(rc, role) if federating_or_unknown_role(rc, role)

workforce_risky_role(_, role) if regex.match(`^(projects|organizations)/[^/]+/roles/`, role)

too_wide(m) if {
	some pat in too_wide_patterns
	regex.match(concat("", [pool_prefix, pat]), m)
}

repo_id_only(m) if matches_any(m, advisory_patterns)

deny contains msg if {
	some rc in lib.managed
	lib.writes(rc)
	some [role, m] in role_members(rc)
	pool_member(m)
	not too_wide(m)
	not pinned(m)
	not repo_id_only(m)
	msg := sprintf("%s: member %s holds %v but is not a pinned workload identity form; bind attribute.repo_ref, attribute.repo_env, attribute.repo_ref_env (GitHub) or attribute.workspace_id_phase / attribute.workspace_phase (Terraform Cloud)", [rc.address, m, role])
}

deny contains msg if {
	some rc in lib.managed
	lib.writes(rc)
	some m in members(rc)
	unpinned_subject(m)
	msg := sprintf("%s: member %s names a subject that trusts more than one workspace and run phase, or more than one repository and ref or environment", [rc.address, m])
}

deny contains msg if {
	some rc in lib.managed
	lib.writes(rc)
	some m in members(rc)
	too_wide(m)
	msg := sprintf("%s: member %s trusts more than one repository + ref/environment (whole pool, owner, repository name, actor, bare ref, audience or raw terraform_* claim); bind attribute.repo_ref, attribute.repo_env or attribute.repo_ref_env (GitHub) or attribute.workspace_id_phase (Terraform Cloud)", [rc.address, m])
}

deny contains msg if {
	some rc in lib.managed
	lib.writes(rc)
	some [role, m] in role_members(rc)
	workforce_member(m)
	workforce_risky_role(rc, role)
	msg := sprintf("%s: workforce pool member %s holds %v, through which it can act as a service account; grant workforce identities direct roles, not service account impersonation", [rc.address, m, role])
}

repo_wide contains msg if {
	some rc in lib.managed
	lib.writes(rc)
	some m in members(rc)
	repo_id_only(m)
	msg := sprintf("%s: member %s trusts every branch, tag and environment of the repository (or every ref of the GitLab project); pin a ref or an environment", [rc.address, m])
}

# Some member of an iam_member or iam_binding is unknown at plan time.
member_unknown(rc) if lib.unknown(rc, "member")

member_unknown(rc) if lib.unknown(rc, "members")

member_unknown(rc) if {
	some u in rc.change.after_unknown.members
	u == true
}

federating(rc) if lib.after(rc, "role") in federating_roles

federating(rc) if lib.unknown(rc, "role")

repo_wide contains msg if {
	some rc in lib.managed
	lib.writes(rc)
	iam_member_or_binding(rc.type)
	federating(rc)
	member_unknown(rc)
	msg := sprintf("%s: a member is unknown at plan time, so it cannot be checked for a too-wide workload identity principalSet", [rc.address])
}

repo_wide contains msg if {
	some rc in lib.managed
	lib.writes(rc)
	iam_policy(rc.type)
	lib.unknown(rc, "policy_data")
	msg := sprintf("%s: policy_data is unknown at plan time, so its members cannot be checked for a too-wide workload identity principalSet", [rc.address])
}
