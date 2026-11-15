# Shared helpers over the HCP Terraform OPA input document.
#
# HCP Terraform passes {plan, run} to OPA: input.plan is the JSON plan
# (`terraform show -json`), so input.plan.resource_changes[] carries
#   address, module_address, mode, type, name,
#   change.actions  (e.g. ["create"], ["update"], ["delete","create"])
#   change.before / change.after  (nested blocks render as lists)
#   change.after_unknown          (true for values known only after apply)
# A policy's query may evaluate code from several .rego files, so policies
# import this package rather than duplicating helpers.
package terraform.lib

import rego.v1

# Managed resources only; data sources never change real infrastructure.
managed contains rc if {
	some rc in input.plan.resource_changes
	rc.mode == "managed"
}

# Resource changes that create or modify an object (incl. replace).
writes(rc) if {
	some action in rc.change.actions
	action in {"create", "update"}
}

creates(rc) if "create" in rc.change.actions

# Destroys the object: plain delete or either half of a replace.
deletes(rc) if "delete" in rc.change.actions

# Managed changes of a type that create or update.
written_of_type(t) := {rc |
	some rc in managed
	rc.type == t
	writes(rc)
}

# The planned value is computed (unknown until apply). Mandatory policies on
# security switches deny an unknown value (unknown_or_not); other rules skip
# it or report it as advisory, because the apply-time value is not plannable.
unknown(rc, attr) if rc.change.after_unknown[attr] == true

# JSON policy documents may be strings (jsonencode) or already-decoded.
policy_doc(raw) := doc if {
	is_string(raw)
	doc := json.unmarshal(raw)
}

policy_doc(raw) := raw if is_object(raw)

# A Statement may be one object or a list of objects.
statements(doc) := doc.Statement if is_array(doc.Statement)

statements(doc) := [doc.Statement] if is_object(doc.Statement)

# Normalise a string-or-list IAM field to a list.
as_list(v) := v if is_array(v)

as_list(v) := [v] if is_string(v)

as_list(v) := [] if v == null

# Planned value of a top-level attribute, null when absent.
after(rc, attr) := object.get(rc.change.after, attr, null)

# The attribute is known at plan time and differs from the expected value.
# Unknown (computed) values are skipped rather than flagged.
known_and_not(rc, attr, expected) if {
	not unknown(rc, attr)
	after(rc, attr) != expected
}

# Fail-closed form for MANDATORY controls: the value is unknown at plan time,
# or known and different from the expected value. A security switch should be
# a plan-known value; an apply-time value cannot be checked, so it is denied.
unknown_or_not(rc, attr, _) if unknown(rc, attr)

unknown_or_not(rc, attr, expected) if known_and_not(rc, attr, expected)

# Message suffix for a rule that uses unknown_or_not.
unknown_hint := " (an unknown value counts as a violation: set a plan-known value)"

# ── OIDC subject pinning (shared by the AWS and GCP federated-trust policies) ─
# TFC: organization:<org>:project:<project>:workspace:<ws>:run_phase:<plan|apply>,
# every segment literal and non-empty.
tfc_subject_pinned(v) if {
	not regex.match(`[*?]`, v)
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

# GitHub: a literal repository (repo:<owner>/<repo>: or repository_id:<id>) and
# a ref:<ref> or environment:<env> segment. Forms such as
# repo:<owner>/<repo>:pull_request, repository_owner_id:<id>:environment:<env>
# or job_workflow_ref:... alone are not pinned.
github_subject_pinned(v) if {
	not regex.match(`[*?]`, v)
	github_repo_pinned(v)
	regex.match(`(^|:)(ref|environment):[^:]+(:|$)`, v)
}

github_repo_pinned(v) if regex.match(`^repo:[^/:]+/[^/:]+:`, v)

github_repo_pinned(v) if regex.match(`(^|:)repository_id:[0-9]+(:|$)`, v)

# The subject has a GitHub shape (default or customised claim template).
github_subject_shape(v) if startswith(v, "repo:")

github_subject_shape(v) if regex.match(`^repository_owner(_id)?:`, v)
