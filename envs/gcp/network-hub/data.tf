# gcp-network-hub reads the org (folders, org_id) and projects (host project IDs
# and numbers) via remote state (audit H3). Apply order: gcp-bootstrap ->
# gcp-organization -> gcp-projects -> gcp-network-hub.
data "terraform_remote_state" "gcp_organization" {
  backend = "cloud"
  config = {
    organization = local.tfc_organization
    workspaces = {
      name = var.organization_workspace_name
    }
  }
}

data "terraform_remote_state" "gcp_projects" {
  backend = "cloud"
  config = {
    organization = local.tfc_organization
    workspaces = {
      name = var.projects_workspace_name
    }
  }
}
