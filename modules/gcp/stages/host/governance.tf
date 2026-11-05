# Host stage: network governance (Shared VPC service projects, VPC Service Controls).
# Part of modules/gcp/stages/host.

# =============================================================================
# SHARED VPC SERVICE PROJECT ATTACHMENTS
# =============================================================================

module "shared_vpc_service_projects" {
  source   = "../../network/shared-vpc-service"
  for_each = var.enable_shared_vpc_host ? var.shared_vpc_service_projects : {}

  host_project_id    = var.project_id
  service_project_id = each.key

  deletion_policy                   = try(each.value.deletion_policy, "ABANDON")
  subnet_iam_bindings               = try(each.value.subnet_iam_bindings, [])
  grant_network_user_to_all_subnets = try(each.value.grant_network_user_to_all_subnets, false)
  network_user_members              = try(each.value.network_user_members, [])
  network_viewer_members            = try(each.value.network_viewer_members, [])
  enable_gke_permissions            = try(each.value.enable_gke_permissions, false)

  # Ensure Shared VPC Host is configured before attaching service projects
  depends_on = [module.vpc]
}

# =============================================================================
# VPC SERVICE CONTROLS
# =============================================================================

module "vpc_service_controls" {
  source   = "../../network/vpc-sc"
  for_each = var.vpc_service_controls

  organization_id            = each.value.organization_id
  access_policy_name         = try(each.value.access_policy_name, null)
  create_access_policy       = try(each.value.create_access_policy, false)
  perimeter_name             = each.key
  perimeter_title            = each.value.perimeter_title
  description                = try(each.value.description, "Managed by Terraform")
  perimeter_type             = try(each.value.perimeter_type, "PERIMETER_TYPE_REGULAR")
  protected_projects         = try(each.value.protected_projects, [])
  restricted_services        = try(each.value.restricted_services, [])
  access_levels              = try(each.value.access_levels, [])
  ingress_policies           = try(each.value.ingress_policies, [])
  egress_policies            = try(each.value.egress_policies, [])
  enable_dry_run             = try(each.value.enable_dry_run, false)
  enable_deletion_protection = try(each.value.enable_deletion_protection, true)
}

