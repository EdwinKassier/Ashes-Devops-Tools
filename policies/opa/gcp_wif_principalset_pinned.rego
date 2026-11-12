# MANDATORY (deny) + ADVISORY (repo_wide): a workload identity principalSet
# must pin one repository AND a ref or an environment. The GitHub provider
# condition pins only the owner (custom.wifProviderTenantPinned), so a
# principalSet on the whole pool (/*), on the owner, on a mutable repository
# name or on a bare ref trusts every repository of the owner. The deny covers
# every google_*_iam_member, google_*_iam_binding and google_*_iam_policy, for
# any role: service account impersonation and direct resource access alike.
#
# Unknown values: a member that embeds a pool created in the same run (the
# pool name holds the project number) is unknown at plan time and cannot be
# required known without blocking the run that creates the pool. Such members
# are not denied; the advisory rule reports them when the role can federate.
package terraform.policies.gcp_wif_principalset_pinned

import rego.v1

import data.terraform.lib

pool_prefix := `^principalSet://iam\.googleapis\.com/projects/[^/]+/locations/global/workloadIdentityPools/[^/]+/`

# Suffixes after the pool prefix that trust more than one repository + ref or
# environment: the whole pool, the owner, a repository name (mutable, and
# every branch of it) and a bare ref (that ref in every repository).
too_wide_patterns := [
	`\*$`,
	`attribute\.repository_owner_id/`,
	`attribute\.repository/`,
	`attribute\.ref/`,
]

# Roles through which a federated principal acts as a service account.
federating_roles := {"roles/iam.workloadIdentityUser", "roles/iam.serviceAccountTokenCreator"}

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

too_wide(m) if {
	some pat in too_wide_patterns
	regex.match(concat("", [pool_prefix, pat]), m)
}

repo_id_only(m) if regex.match(concat("", [pool_prefix, `attribute\.repository_id/[^/]+$`]), m)

deny contains msg if {
	some rc in lib.managed
	lib.writes(rc)
	some m in members(rc)
	too_wide(m)
	msg := sprintf("%s: member %s trusts more than one repository + ref/environment (whole pool, owner, repository name or bare ref); bind attribute.repo_ref, attribute.repo_env or attribute.repo_ref_env", [rc.address, m])
}

repo_wide contains msg if {
	some rc in lib.managed
	lib.writes(rc)
	some m in members(rc)
	repo_id_only(m)
	msg := sprintf("%s: member %s trusts every branch, tag and environment of the repository; pin a ref or an environment", [rc.address, m])
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
