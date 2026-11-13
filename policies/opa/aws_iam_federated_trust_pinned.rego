# MANDATORY: a role that trusts an OIDC web-identity provider must pin the
# audience and an exact subject. Any wildcard in a subject (`*` or `?`, under
# any operator), a TFC subject without a literal organization, project,
# workspace and run phase, or a GitHub subject without a literal repository
# and a literal ref or environment lets another tenant, workspace, run phase,
# branch or pull request assume the role: a persistence backdoor.
#
# A trust document that is unknown at plan time cannot be checked, so it is
# denied, except in a run that also creates an OIDC provider or the AWS
# organization. Those runs are the legitimate first applies whose trust is
# unknown until apply (a GitHub deploy role naming its new provider; the
# management-account roles of a greenfield organization). The advisory twin
# (federated_unknown) reports every unknown trust, including those.
package terraform.policies.aws_iam_federated_trust_pinned

import rego.v1

import data.terraform.lib

web_identity_action := "sts:assumerolewithwebidentity"

# An IAM action pattern matches web identity: IAM action names ignore case,
# and `*` (any run) and `?` (one character) are the only wildcards; they also
# match `:`. Every other character is literal.
matches_web_identity(pattern) if regex.match(iam_pattern_regex(pattern), web_identity_action)

iam_pattern_regex(pattern) := concat("", ["^", wildcards, "$"]) if {
	escaped := regex.replace(lower(pattern), `[.+^$()|\[\]{}\\]`, `\$0`)
	wildcards := replace(replace(escaped, "*", ".*"), "?", ".")
}

allows_web_identity(stmt) if {
	some action in lib.as_list(object.get(stmt, "Action", null))
	matches_web_identity(action)
}

# NotAction allows every action it does not list.
allows_web_identity(stmt) if {
	not_actions := lib.as_list(object.get(stmt, "NotAction", null))
	count(not_actions) > 0
	not any_matches_web_identity(not_actions)
}

any_matches_web_identity(actions) if {
	some action in actions
	matches_web_identity(action)
}

# A federated principal other than a SAML provider (which cannot issue a
# web-identity token).
web_identity_principal(stmt) if {
	some p in lib.as_list(object.get(object.get(stmt, "Principal", {}), "Federated", null))
	not contains(p, ":saml-provider/")
}

federated_web_identity(stmt) if {
	stmt.Effect == "Allow"
	web_identity_principal(stmt)
	allows_web_identity(stmt)
}

op_matches(op) if op in {"StringEquals", "StringLike", "ForAnyValue:StringEquals", "ForAnyValue:StringLike", "ForAllValues:StringEquals", "ForAllValues:StringLike"}

# [key, value] pairs of condition keys under StringEquals / StringLike (incl.
# the ForAnyValue: / ForAllValues: forms) whose key ends with the suffix.
cond_pairs(stmt, suffix) := [[key, v] |
	some op, kv in object.get(stmt, "Condition", {})
	op_matches(op)
	some key, raw in kv
	endswith(key, suffix)
	some v in lib.as_list(raw)
]

# ── Subject pinning ─────────────────────────────────────────────────────────
# Any wildcard anywhere, on any issuer. Under StringEquals a `*` is literal and
# never matches a real token, so denying it there costs nothing.
unpinned_subject(_, v) if contains(v, "*")

unpinned_subject(_, v) if contains(v, "?")

# TFC: organization:<org>:project:<project>:workspace:<ws>:run_phase:<plan|apply>
unpinned_subject(_, v) if {
	startswith(v, "organization:")
	not tfc_pinned(v)
}

tfc_pinned(v) if {
	parts := split(v, ":")
	count(parts) == 8
	parts[0] == "organization"
	parts[2] == "project"
	parts[4] == "workspace"
	parts[6] == "run_phase"
	parts[7] in {"plan", "apply"}
	every i in [1, 3, 5] {
		parts[i] != ""
	}
}

# GitHub: repo:<owner>/<repo>:<context> or a customised template that holds
# repository_id:<id>; the context must hold ref:<ref> or environment:<env>.
github_subject(key, _) if startswith(key, "token.actions.githubusercontent.com")

github_subject(_, v) if startswith(v, "repo:")

github_subject(_, v) if regex.match(`^repository_owner(_id)?:`, v)

unpinned_subject(key, v) if {
	github_subject(key, v)
	not github_pinned(v)
}

github_pinned(v) if {
	github_repo_pinned(v)
	regex.match(`(^|:)(ref|environment):[^:]+(:|$)`, v)
}

github_repo_pinned(v) if regex.match(`^repo:[^/:]+/[^/:]+:`, v)

github_repo_pinned(v) if regex.match(`(^|:)repository_id:[0-9]+(:|$)`, v)

# ── Rules ───────────────────────────────────────────────────────────────────
federated_statements contains [rc.address, stmt] if {
	some rc in lib.written_of_type("aws_iam_role")
	raw := lib.after(rc, "assume_role_policy")
	raw != null
	doc := lib.policy_doc(raw)
	some stmt in lib.statements(doc)
	federated_web_identity(stmt)
}

deny contains msg if {
	some [address, stmt] in federated_statements
	count(cond_pairs(stmt, ":aud")) == 0
	msg := sprintf("%s: federated (web-identity) trust has no audience (:aud) condition", [address])
}

deny contains msg if {
	some [address, stmt] in federated_statements
	count(cond_pairs(stmt, ":sub")) == 0
	msg := sprintf("%s: federated (web-identity) trust has no subject (:sub) condition", [address])
}

deny contains msg if {
	some [address, stmt] in federated_statements
	some [key, v] in cond_pairs(stmt, ":sub")
	unpinned_subject(key, v)
	msg := sprintf("%s: federated (web-identity) trust has an unpinned subject %q (no wildcards; TFC needs a literal organization, project, workspace and run_phase plan|apply; GitHub needs a literal repository and a ref: or environment: context)", [address, v])
}

# ── Unknown trust documents ─────────────────────────────────────────────────
unknown_trust contains rc if {
	some rc in lib.written_of_type("aws_iam_role")
	lib.unknown(rc, "assume_role_policy")
}

# The run creates a resource that legitimately makes a trust unknown until apply.
first_apply_dependency_created if {
	some rc in lib.managed
	rc.type in {"aws_iam_openid_connect_provider", "aws_organizations_organization"}
	lib.creates(rc)
}

deny contains msg if {
	some rc in unknown_trust
	not first_apply_dependency_created
	msg := sprintf("%s: assume_role_policy is unknown at plan time, so federated-trust pinning cannot be checked; build the trust from plan-known values (an unknown trust is allowed only in a run that creates an OIDC provider or the organization)", [rc.address])
}

# Advisory twin: every trust whose policy is unknown at plan time.
federated_unknown contains msg if {
	some rc in unknown_trust
	msg := sprintf("%s: assume_role_policy is unknown at plan time; federated-trust pinning cannot be verified (re-run after the provider exists)", [rc.address])
}
