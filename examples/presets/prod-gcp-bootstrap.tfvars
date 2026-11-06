# Production hardening overlay for envs/gcp/bootstrap. Apply IN ADDITION to your own tfvars:
#   terraform -chdir=envs/gcp/bootstrap plan -var-file=your.tfvars -var-file=../../../examples/presets/prod-gcp-bootstrap.tfvars
#
# Per-stage plan/apply service accounts with run-phase-scoped WIF bindings are now
# the default (audit C2), so the old enable_privilege_split toggle is gone.
#
# Keep the GitHub Actions -> GCP federation pool OFF unless a workflow needs it.
# When enabled it is bound only to the read-only organization-plan SA, pinned to
# the immutable repository_id / repository_owner_id.
enable_github_wif = false

# Bind every control-plane workspace and every production workload workspace by
# its IMMUTABLE TFC workspace ID, not its (renameable, squattable) name. Mark
# production environments with is_production = true in your environments map:
# a check warns while any of their workspaces is still bound by name.
# The ws-REPLACEME placeholders below are REJECTED by variable validation on
# purpose: replace each with the real ID (tfc-admin output workspace_ids, or
# TFC UI > workspace > Settings > ID) or the plan fails.
tfc_workspace_ids = {
  "gcp-bootstrap"     = "ws-REPLACEME"
  "gcp-organization"  = "ws-REPLACEME"
  "gcp-projects"      = "ws-REPLACEME"
  "gcp-network-hub"   = "ws-REPLACEME"
  "gcp-workload-prod" = "ws-REPLACEME"
}

# Workload VPC-SC: each environment gets its own folder-scoped access policy
# (created by gcp-organization). Keep the org-wide legacy grant off.
enable_scoped_access_policies          = true
enable_legacy_org_access_policy_grants = false

# Folder-IAM delegation is bound per folder by gcp-organization; keep the legacy
# org-node binding off.
enable_org_level_folder_iam_delegation = false

# Just-in-time org admin via Privileged Access Manager (pair with enable_pam in
# prod-gcp-organization.tfvars).
enable_pam = true

# Pass 2 onwards: no standing human impersonation of the bootstrap apply SA.
enable_phase0_admin_impersonation = false

# Guardrail owner (separate mode is the default): only this PAM-gated group may
# impersonate the guardrails SA that owns the IAM deny policies. The placeholder
# is rejected by validation until you replace it.
guardrail_owner_mode    = "separate"
guardrail_owner_members = ["group:REPLACE-guardrail-owners@your-domain.invalid"]
