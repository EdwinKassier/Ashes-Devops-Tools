# gcp-bootstrap root: phase-0 automation foundation.
#
# Extracted from gcp-organization so the WIF / Terraform-admin-SA
# control plane has its own state and blast radius. It is the PRODUCER of the
# admin project, the Terraform admin SA, and the WIF pools; gcp-organization
# reads these via terraform_remote_state. Apply this root before gcp-organization.

# Every control-plane workspace (gcp-bootstrap, gcp-organization,
# gcp-projects, gcp-network-hub) and every gcp-workload-<env> gets its OWN plan
# (read-only) and apply SA, bound per run phase. Workload SAs receive no
# org-level role; gcp-projects grants them roles on their env folder.
module "bootstrap" {
  source = "../../../modules/gcp/stages/bootstrap"

  project_prefix  = local.project_prefix
  org_id          = data.google_organization.org.org_id
  billing_account = data.google_billing_account.billing.id
  admin_email     = local.admin_email

  # Terraform Cloud dynamic credentials
  enable_tfc_oidc       = var.enable_tfc_oidc
  tfc_organization      = local.tfc_organization
  tfc_hostname          = var.tfc_hostname
  tfc_organization_id   = var.tfc_organization_id
  tfc_project_ids       = var.tfc_project_ids
  tfc_workspace_ids     = var.tfc_workspace_ids
  workload_environments = toset(keys(local.environments))

  # Environments marked is_production: a check warns while their workspaces (and
  # the control-plane workspaces) are still WIF-bound by name, not ID.
  production_workload_environments = toset([for k, e in local.environments : k if e.is_production])

  # Workload VPC-SC: each environment gets its own folder-scoped access policy
  # (created by gcp-organization). The org-wide grant is legacy, opt-in only.
  enable_scoped_access_policies          = var.enable_scoped_access_policies
  vpc_sc_access_policy_id                = var.vpc_sc_access_policy_id
  enable_legacy_org_access_policy_grants = var.enable_legacy_org_access_policy_grants

  # projects-apply folder-IAM delegation is bound per folder by gcp-organization;
  # the org-node binding is legacy, opt-in only.
  enable_org_level_folder_iam_delegation = var.enable_org_level_folder_iam_delegation

  # Just-in-time org admin (PAM) managed by gcp-organization.
  enable_pam = var.enable_pam

  # Network Connectivity Center roles on the network-hub (shared folder) and
  # workload (env folder) SAs, when the opt-in NCC connectivity is in use.
  enable_network_connectivity_center = local.enable_network_connectivity_center

  # Phase-0 human impersonation of terraform-admin (turn off on pass 2).
  enable_phase0_admin_impersonation     = var.enable_phase0_admin_impersonation
  phase0_admin_impersonation_expires_at = local.phase0_admin_impersonation_expires_at

  # Deny-policy ownership: a separate guardrails SA holds roles/iam.denyAdmin.
  guardrail_owner_mode    = var.guardrail_owner_mode
  guardrail_owner_members = var.guardrail_owner_members

  # Principal access boundary for the automation SAs (gcp-organization).
  enable_principal_access_boundary = local.enable_principal_access_boundary

  # GitHub WIF — off by default (unused); see variables.tf.
  enable_github_wif          = var.enable_github_wif
  github_org                 = var.github_org
  github_repo                = var.github_repo
  github_repository_id       = var.github_repository_id
  github_repository_owner_id = var.github_repository_owner_id
}
