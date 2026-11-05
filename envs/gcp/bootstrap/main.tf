# gcp-bootstrap root: phase-0 automation foundation.
#
# Extracted from gcp-organization (audit H3) so the WIF / Terraform-admin-SA
# control plane has its own state and blast radius. It is the PRODUCER of the
# admin project, the Terraform admin SA, and the WIF pools; gcp-organization
# reads these via terraform_remote_state. Apply this root before gcp-organization.

# Audit C2: every control-plane workspace (gcp-bootstrap, gcp-organization,
# gcp-projects, gcp-network-hub) and every gcp-workload-<env> gets its OWN plan
# (read-only) and apply SA, bound per run phase. Workload SAs receive no
# org-level role; gcp-projects grants them roles on their env folder.
module "bootstrap" {
  source = "../../../modules/gcp/stages/bootstrap"

  project_prefix  = var.project_prefix
  org_id          = data.google_organization.org.org_id
  billing_account = data.google_billing_account.billing.id
  admin_email     = var.admin_email

  # Terraform Cloud dynamic credentials
  enable_tfc_oidc       = var.enable_tfc_oidc
  tfc_organization      = var.tfc_organization
  tfc_organization_id   = var.tfc_organization_id
  tfc_project_ids       = var.tfc_project_ids
  tfc_workspace_ids     = var.tfc_workspace_ids
  workload_environments = toset(keys(var.environments))

  vpc_sc_access_policy_id = var.vpc_sc_access_policy_id

  # GitHub WIF — off by default (unused); see variables.tf.
  enable_github_wif          = var.enable_github_wif
  github_org                 = var.github_org
  github_repo                = var.github_repo
  github_repository_id       = var.github_repository_id
  github_repository_owner_id = var.github_repository_owner_id
}
