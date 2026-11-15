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
# production workspace, widened team access, local or agent execution, agent
# pools, rewired protected workspaces, env vars that steer credentials, the
# CLI or the runner), or a control-plane or production apply of code that did
# not come from VCS, stops the run until a user with
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

# PREVIEW: a run that can apply on a VCS-connected workspace tagged
# layer:control-plane, layer:bootstrap or tier:production must carry a commit
# SHA (it came from the connected repository, not an API-uploaded
# configuration version). The run field is confirmed by the docs only, so the
# rule sits in this overridable set until a sandbox run confirms it; then it
# moves to the hard-gate policies/opa set (docs/known-gaps.md).
policy "tfc_vcs_run_only" {
  query             = "data.terraform.policies.tfc_vcs_run_only.deny"
  enforcement_level = "mandatory"
}
