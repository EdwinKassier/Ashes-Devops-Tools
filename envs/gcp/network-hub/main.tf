# gcp-network-hub root: hub VPC, DNS anchor, and the hub VPC-SC perimeter.
#
# Extracted from gcp-organization. Reads org folders/org_id and the
# host project IDs/numbers from the upstream roots via remote state. Apply last
# of the control-plane roots, after gcp-projects.

locals {
  # Remote state when read (count = 1), else the supplied contract. try() only
  # selects the source — it does not unify the two object types — and a failed
  # read still errors at plan time.
  org      = try(data.terraform_remote_state.gcp_organization[0].outputs, local.organization_contract)
  projects = try(data.terraform_remote_state.gcp_projects[0].outputs, local.projects_contract)
}

module "network_hub" {
  source = "../../../modules/gcp/stages/network-hub"

  project_prefix = local.project_prefix
  default_region = local.default_region

  hub_project_id = local.projects.project_ids["shared-hub"]
  dns_project_id = local.projects.project_ids["shared-dns"]
  # VPC-SC / ACM require numeric project numbers, not ID strings.
  spoke_project_numbers = {
    for env_key in sort(keys(local.environments)) :
    env_key => local.projects.project_numbers["${env_key}-host"]
  }

  org_id  = local.org.org_id
  folders = local.org.folders

  hub_vpc_cidr_block     = local.hub_vpc_cidr_block
  dns_hub_vpc_cidr_block = local.dns_hub_vpc_cidr_block

  vpc_sc_access_policy_name = var.vpc_sc_access_policy_name
  vpc_sc_enable_dry_run     = var.vpc_sc_enable_dry_run

  vpc_sc_additional_restricted_services = var.vpc_sc_additional_restricted_services
  vpc_sc_ingress_identities             = var.vpc_sc_ingress_identities

  vpc_sc_dry_run_additional_restricted_services = var.vpc_sc_dry_run_additional_restricted_services
}

# Nothing else ties production to an enforced perimeter. The hub perimeter
# protects the hub/DNS projects every environment peers with, so if any
# environment is marked is_production the hub perimeter must exist AND be
# enforced. A check block WARNS (it does not
# fail the plan) so a staged rollout under dry-run stays possible.
check "hub_vpc_sc_enforced_when_prod_present" {
  assert {
    condition = !anytrue([for e in values(local.environments) : e.is_production]) || (
      var.vpc_sc_access_policy_name != null && !var.vpc_sc_enable_dry_run
    )
    error_message = "A production environment (is_production = true) is present but the hub VPC-SC perimeter is ${var.vpc_sc_access_policy_name == null ? "NOT CREATED (vpc_sc_access_policy_name is null)" : "in DRY-RUN (vpc_sc_enable_dry_run = true)"}. Dry-run gives no exfiltration protection: validate the violation logs, then set vpc_sc_enable_dry_run = false (use vpc_sc_dry_run_additional_restricted_services to keep staging further changes)."
  }
}
