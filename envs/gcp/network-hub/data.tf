# gcp-network-hub reads the org (folders, org_id) and projects (host project IDs
# and numbers) via remote state. Apply order: gcp-bootstrap ->
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

# Spoke networks that already exist. The hub side of a peering can only be
# created once its peer network exists, and the spoke network is created by
# gcp-workload-<env>, which applies after this root. So each run peers the hub
# with the spokes that exist; an environment's first workload apply is followed
# by one more run of this workspace. Listing needs compute.networks.list on the
# environment host projects (roles/compute.viewer on the environment folders,
# granted to the network-hub SAs by gcp-projects).
locals {
  spoke_peering_candidates = {
    for env in sort(keys(local.environments)) : env => {
      project_id   = try(local.projects.project_ids["${env}-host"], "")
      network_name = "${local.project_prefix}-${env}-vpc"
    }
    if local.create_spoke_peerings &&
    coalesce(try(local.cfg.environment_connectivity[env], null), local.cfg.network_connectivity, "peering") == "peering" &&
    try(local.projects.project_ids["${env}-host"], "") != ""
  }
}

data "google_compute_networks" "spoke" {
  for_each = local.spoke_peering_candidates

  project = each.value.project_id
}
