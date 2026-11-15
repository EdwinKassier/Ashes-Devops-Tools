# MANDATORY (overridable set, PREVIEW): a run that can apply on a VCS-connected
# control-plane, bootstrap or production workspace must come from the
# connected repository.
#
# The approvers team holds runs = apply on those workspaces. The CLI refuses
# `terraform apply` on a VCS-connected workspace, but the API accepts an
# uploaded configuration version. Without this rule an approver could upload
# code, queue a run and confirm it, and no pull request, CODEOWNERS review or
# CI gate would see that code.
#
# Fields read (HCP Terraform "Define OPA policies", Terraform run data,
# checked 2026-11-12):
#   run.commit_sha            "The checksum hash (SHA) that identifies the commit"
#   run.speculative           "Whether the plan associated with the run is a
#                             speculative plan only"
#   run.workspace.tags        "The list of tag names for the workspace"
#   run.workspace.vcs_repo    "Data associated with a VCS repository connected
#                             to the workspace" ... "This value can be null."
# The configuration versions API shows an API-created version with
# "source": "tfe-api" and no ingress attributes (the commit data), and its
# create request takes no commit field. So a run on an uploaded version has
# no commit SHA. PREVIEW: that is not confirmed on a real run, so the rule
# lives in the overridable policies/opa-destructive set (the security team
# overrides a wrong deny) and moves to the hard-gate policies/opa set once a
# sandbox run confirms the field (docs/known-gaps.md).
#
# run.message is NOT read: the API caller sets it.
#
# Scope: the tags tfc-admin sets (layer:control-plane, layer:bootstrap,
# tier:production), as in tfc_admin_guard. A speculative plan cannot apply,
# and a workspace with no VCS connection (vcs_repo null, for example a
# local-mode gcp-bootstrap) is out of scope. A plan with no run data (opa
# eval, the policy tests) is not judged.
package terraform.policies.tfc_vcs_run_only

import rego.v1

protected_tags := {"layer:control-plane", "layer:bootstrap", "tier:production"}

run := input.run if is_object(input.run)

# Missing speculative counts as a run that can apply (fail closed).
can_apply if not run.speculative == true

vcs_connected if is_object(run.workspace.vcs_repo)

protected if {
	some t in run.workspace.tags
	t in protected_tags
}

has_commit if {
	is_string(run.commit_sha)
	run.commit_sha != ""
}

deny contains msg if {
	run
	can_apply
	vcs_connected
	protected
	not has_commit
	msg := sprintf("run %s on workspace %s has no commit SHA: it did not come from the connected repository (an API-uploaded configuration version), and a control-plane, bootstrap or production workspace applies only reviewed code from VCS. Merge the change and queue the run from VCS", [object.get(run, "id", "?"), object.get(run.workspace, "name", "?")])
}
