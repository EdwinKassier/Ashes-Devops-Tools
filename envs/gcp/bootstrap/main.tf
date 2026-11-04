# gcp-bootstrap root: phase-0 automation foundation.
#
# Extracted from gcp-organization (audit H3) so the WIF / Terraform-admin-SA
# control plane has its own state and blast radius. It is the PRODUCER of the
# admin project, the Terraform admin SA, and the WIF pools; gcp-organization
# reads these via terraform_remote_state. Apply this root before gcp-organization.

locals {
  # Workspaces that receive WIF trust: this bootstrap workspace, the organization
  # workspace, and one per application environment.
  tfc_workspaces = concat(
    ["gcp-bootstrap", "gcp-organization"],
    [for env_key in sort(keys(var.environments)) : "gcp-workload-${env_key}"]
  )
}

module "bootstrap" {
  source = "../../../modules/gcp/stages/bootstrap"

  project_prefix         = var.project_prefix
  org_id                 = data.google_organization.org.org_id
  billing_account        = data.google_billing_account.billing.id
  admin_email            = var.admin_email
  github_org             = var.github_org
  github_repo            = var.github_repo
  tfc_organization       = var.tfc_organization
  tfc_workspaces         = local.tfc_workspaces
  enable_tfc_oidc        = var.enable_tfc_oidc
  enable_privilege_split = var.enable_privilege_split
}
