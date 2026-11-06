# gcp-network-hub reads the org (folders, org_id) and projects (host project IDs
# and numbers) via remote state (audit H3). Apply order: gcp-bootstrap ->
# gcp-organization -> gcp-projects -> gcp-network-hub.
#
# Stage contract override (FAST-style): a supplied organization_contract /
# projects_contract (variable or gcp.contracts.<layer> in config/landing-zone.yaml)
# replaces the matching read (count = 0).
locals {
  organization_contract = var.organization_contract != null ? var.organization_contract : local.cfg.organization_contract
  projects_contract     = var.projects_contract != null ? var.projects_contract : local.cfg.projects_contract
}

data "terraform_remote_state" "gcp_organization" {
  count   = local.organization_contract == null ? 1 : 0
  backend = "cloud"
  config = {
    organization = local.tfc_organization
    workspaces = {
      name = var.organization_workspace_name
    }
  }
}

data "terraform_remote_state" "gcp_projects" {
  count   = local.projects_contract == null ? 1 : 0
  backend = "cloud"
  config = {
    organization = local.tfc_organization
    workspaces = {
      name = var.projects_workspace_name
    }
  }
}
