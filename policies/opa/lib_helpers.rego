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

# The planned value is computed (unknown until apply). Policies skip unknown
# values instead of failing on them; the apply-time value is not plannable.
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
