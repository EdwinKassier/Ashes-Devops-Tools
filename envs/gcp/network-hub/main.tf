# gcp-network-hub root: hub VPC, DNS anchor, and the hub VPC-SC perimeter.
#
# Extracted from gcp-organization (audit H3). Reads org folders/org_id and the
# host project IDs/numbers from the upstream roots via remote state. Apply last
# of the control-plane roots, after gcp-projects.

locals {
  org      = data.terraform_remote_state.gcp_organization.outputs
  projects = data.terraform_remote_state.gcp_projects.outputs
}

module "network_hub" {
  source = "../../../modules/gcp/stages/network-hub"

  project_prefix = var.project_prefix
  default_region = var.default_region

  hub_project_id = local.projects.project_ids["shared-hub"]
  dns_project_id = local.projects.project_ids["shared-dns"]
  # VPC-SC / ACM require numeric project numbers, not ID strings.
  spoke_project_numbers = {
    for env_key in sort(keys(var.environments)) :
    env_key => local.projects.project_numbers["${env_key}-host"]
  }

  org_id  = local.org.org_id
  folders = local.org.folders

  hub_vpc_cidr_block     = var.hub_vpc_cidr_block
  dns_hub_vpc_cidr_block = var.dns_hub_vpc_cidr_block

  vpc_sc_access_policy_name = var.vpc_sc_access_policy_name
  vpc_sc_enable_dry_run     = var.vpc_sc_enable_dry_run

  vpc_sc_additional_restricted_services = var.vpc_sc_additional_restricted_services
  vpc_sc_ingress_identities             = var.vpc_sc_ingress_identities
}
