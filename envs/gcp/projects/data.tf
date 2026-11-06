# gcp-projects reads its upstreams via remote state. Apply order:
# gcp-bootstrap -> gcp-organization -> gcp-projects.
#
# Stage contract override (FAST-style): a supplied bootstrap_contract /
# organization_contract (variable or gcp.contracts.<layer> in
# config/landing-zone.yaml) replaces the matching read (count = 0).
locals {
  bootstrap_contract    = var.bootstrap_contract != null ? var.bootstrap_contract : local.cfg.bootstrap_contract
  organization_contract = var.organization_contract != null ? var.organization_contract : local.cfg.organization_contract
}

data "terraform_remote_state" "gcp_bootstrap" {
  count   = local.bootstrap_contract == null ? 1 : 0
  backend = "cloud"
  config = {
    organization = local.tfc_organization
    workspaces = {
      name = var.bootstrap_workspace_name
    }
  }
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
