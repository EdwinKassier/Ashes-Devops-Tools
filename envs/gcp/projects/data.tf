# gcp-projects reads its upstreams via remote state (audit H3). Apply order:
# gcp-bootstrap -> gcp-organization -> gcp-projects.
data "terraform_remote_state" "gcp_bootstrap" {
  backend = "cloud"
  config = {
    organization = var.tfc_organization
    workspaces = {
      name = var.bootstrap_workspace_name
    }
  }
}

data "terraform_remote_state" "gcp_organization" {
  backend = "cloud"
  config = {
    organization = var.tfc_organization
    workspaces = {
      name = var.organization_workspace_name
    }
  }
}
