# HCP Terraform OPA policy set "<prefix>destructive-change-guard" (attached by
# envs/tfc-admin with policies_path = "policies/opa-destructive").
#
# A VCS policy set reads the policies.hcl in its own policies_path, so the
# destroy guard lives in its own directory: this set is OVERRIDABLE
# (overridable = true), while the policies/opa guardrails set is not.
# lib_helpers.rego is a byte-identical copy of policies/opa/lib_helpers.rego
# (scripts/check-consistency.sh enforces it).
#
# mandatory: a stateful delete or replace, or a change that weakens the HCP
# Terraform layer (detaching a policy set, auto-apply on a control-plane or
# production workspace, widened team access), stops the run until a user with
# Manage Policy Overrides (the hand-created security team, security_team_id)
# overrides it. Full guide: docs/architecture/policy-as-code.md.

policy "destroy_guard" {
  query             = "data.terraform.policies.destroy_guard.deny"
  enforcement_level = "mandatory"
}

policy "tfc_admin_guard" {
  query             = "data.terraform.policies.tfc_admin_guard.deny"
  enforcement_level = "mandatory"
}
