# MANDATORY: a role that trusts an OIDC web-identity provider must pin the
# audience and an exact subject. Any wildcard in a subject (`*` or `?`, under
# any operator), a TFC subject without a literal organization, project,
# workspace and run phase, or a GitHub subject without a literal repository
# and a literal ref or environment lets another tenant, workspace, run phase,
# branch or pull request assume the role: a persistence backdoor.
#
# The pins count only under StringEquals / StringLike (and their ForAnyValue:
# forms; ForAllValues: is true when the key is absent), with a condition key
# (case-insensitive) whose issuer is one of the statement's Federated
# providers. The audience may not hold a wildcard either. A web-identity
# action on any principal ("*" or AWS "*") is denied outright.
#
# A trust document that is unknown at plan time cannot be checked, so it is
# denied, unless the role itself is created in this run and the same run
# creates an OIDC provider or the AWS organization in the role's own module
# instance or in a module below it. Those are the
# legitimate first applies whose trust is unknown until apply (a GitHub deploy
# role naming its new provider in app-services; the management-account roles
# of a greenfield organization, one module above module.organization). The
# advisory twin (federated_unknown) reports every unknown trust.
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

# Federated principals of the statement.
federated_principals(stmt) := lib.as_list(object.get(object.get(stmt, "Principal", {}), "Federated", null))

# A federated principal other than a SAML provider (which cannot issue a
# web-identity token).
web_identity_principal(stmt) if {
	some p in federated_principals(stmt)
	not contains(p, ":saml-provider/")
}

federated_web_identity(stmt) if {
	stmt.Effect == "Allow"
	web_identity_principal(stmt)
	allows_web_identity(stmt)
}

# Any principal: "*", {"AWS": "*"} or {"Federated": "*"} (also inside a
# list), or a NotPrincipal (every principal it does not list).
any_principal(stmt) if stmt.Principal == "*"

any_principal(stmt) if {
	some p in federated_principals(stmt)
	p == "*"
}

any_principal(stmt) if object.get(stmt, "NotPrincipal", null) != null

any_principal(stmt) if {
	some p in lib.as_list(object.get(object.get(stmt, "Principal", {}), "AWS", null))
	p == "*"
}

# Issuer host paths of the statement's providers, lowercased: the part after
# "oidc-provider/" of an IAM OIDC provider ARN, or the bare provider name
# (accounts.google.com, cognito-identity.amazonaws.com).
provider_hosts(stmt) := {lower(host) |
	some p in federated_principals(stmt)
	is_string(p)
	host := provider_host(p)
}

provider_host(p) := substring(p, i + count("oidc-provider/"), -1) if {
	i := indexof(p, "oidc-provider/")
	i >= 0
}

provider_host(p) := p if not contains(p, "oidc-provider/")

# Pins: StringEquals / StringLike and their ForAnyValue: forms. ForAllValues:
# is true when the key is absent from the request, so it pins nothing.
op_matches(op) if op in {"StringEquals", "StringLike", "ForAnyValue:StringEquals", "ForAnyValue:StringLike"}

# [issuer, value] pairs of pin conditions whose key (lowercased) is
# "<issuer><suffix>" for an issuer that is one of the statement's providers.
cond_pairs(stmt, suffix) := [[issuer, v] |
	hosts := provider_hosts(stmt)
	some op, kv in object.get(stmt, "Condition", {})
	op_matches(op)
	some raw_key, raw in kv
	key := lower(raw_key)
	endswith(key, suffix)
	issuer := substring(key, 0, count(key) - count(suffix))
	issuer in hosts
	some v in lib.as_list(raw)
]

github_issuer := "token.actions.githubusercontent.com"

# ── Subject and audience pinning ────────────────────────────────────────────
# Any wildcard anywhere, on any issuer. Under StringEquals a `*` is literal and
# never matches a real token, so denying it there costs nothing.
wildcard(v) if regex.match(`[*?]`, v)

unpinned_subject(_, v) if wildcard(v)

unpinned_subject(_, v) if {
	startswith(v, "organization:")
	not lib.tfc_subject_pinned(v)
}

# GitHub subject: the issuer is github.com's, or the value has a GitHub shape
# (GitHub Enterprise Server and other issuers are recognised by shape only).
unpinned_subject(issuer, v) if {
	issuer == github_issuer
	not lib.github_subject_pinned(v)
}

unpinned_subject(_, v) if {
	lib.github_subject_shape(v)
	not lib.github_subject_pinned(v)
}

# ── Rules ───────────────────────────────────────────────────────────────────
trust_statements contains [rc.address, stmt] if {
	some rc in lib.written_of_type("aws_iam_role")
	raw := lib.after(rc, "assume_role_policy")
	raw != null
	doc := lib.policy_doc(raw)
	some stmt in lib.statements(doc)
}

federated_statements contains [address, stmt] if {
	some [address, stmt] in trust_statements
	federated_web_identity(stmt)
}

deny contains msg if {
	some [address, stmt] in trust_statements
	stmt.Effect == "Allow"
	any_principal(stmt)
	allows_web_identity(stmt)
	msg := sprintf("%s: trust allows web identity (sts:AssumeRoleWithWebIdentity) to any principal; name one Federated OIDC provider", [address])
}

deny contains msg if {
	some [address, stmt] in federated_statements
	count(cond_pairs(stmt, ":aud")) == 0
	msg := sprintf("%s: federated (web-identity) trust has no audience (<provider>:aud) condition under StringEquals or StringLike", [address])
}

deny contains msg if {
	some [address, stmt] in federated_statements
	count(cond_pairs(stmt, ":sub")) == 0
	msg := sprintf("%s: federated (web-identity) trust has no subject (<provider>:sub) condition under StringEquals or StringLike", [address])
}

deny contains msg if {
	some [address, stmt] in federated_statements
	some [_, v] in cond_pairs(stmt, ":aud")
	wildcard(v)
	msg := sprintf("%s: federated (web-identity) trust has a wildcard audience %q", [address, v])
}

deny contains msg if {
	some [address, stmt] in federated_statements
	some [issuer, v] in cond_pairs(stmt, ":sub")
	unpinned_subject(issuer, v)
	msg := sprintf("%s: federated (web-identity) trust has an unpinned subject %q (no wildcards; TFC needs a literal organization, project, workspace and run_phase plan|apply; GitHub needs a literal repository and a ref: or environment: context)", [address, v])
}

# ── Unknown trust documents ─────────────────────────────────────────────────
unknown_trust contains rc if {
	some rc in lib.written_of_type("aws_iam_role")
	lib.unknown(rc, "assume_role_policy")
}

module_of(rc) := object.get(rc, "module_address", "")

# dep is in the role's module instance or in a module below it.
same_or_below(rc, dep) if module_of(rc) == module_of(dep)

same_or_below(rc, _) if module_of(rc) == ""

same_or_below(rc, dep) if {
	module_of(rc) != ""
	startswith(module_of(dep), concat("", [module_of(rc), "."]))
}

# The run creates, in the role's module or below it, a resource that
# legitimately makes the trust unknown until apply.
first_apply_dependency(rc) if {
	some dep in lib.managed
	dep.type in {"aws_iam_openid_connect_provider", "aws_organizations_organization"}
	lib.creates(rc)
	lib.creates(dep)
	same_or_below(rc, dep)
}

deny contains msg if {
	some rc in unknown_trust
	not first_apply_dependency(rc)
	msg := sprintf("%s: assume_role_policy is unknown at plan time, so federated-trust pinning cannot be checked; build the trust from plan-known values (an unknown trust is allowed only on a new role when the same run creates an OIDC provider or the organization in the role's module or below it)", [rc.address])
}

# Advisory twin: every trust whose policy is unknown at plan time.
federated_unknown contains msg if {
	some rc in unknown_trust
	msg := sprintf("%s: assume_role_policy is unknown at plan time; federated-trust pinning cannot be verified (re-run after the provider exists)", [rc.address])
}
