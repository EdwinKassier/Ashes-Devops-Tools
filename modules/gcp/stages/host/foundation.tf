# Host stage: network foundation (VPC, three-tier subnets, NAT, PSA, PSC).
# Part of modules/gcp/stages/host (see main.tf for locals and guards).

module "vpc" {
  source = "../../network/vpc"
  count  = var.enable_networking ? 1 : 0

  project_id = var.project_id
  vpc_name   = var.vpc_name

  # Enterprise features
  enable_shared_vpc_host          = var.enable_shared_vpc_host
  delete_default_routes_on_create = true
  enable_deletion_protection      = var.enable_deletion_protection
}

# -----------------------------------------------------------------------------
# SUBNETS (Three-Tier Architecture)
# -----------------------------------------------------------------------------

# Public subnets
module "public_subnets" {
  source   = "../../network/subnet"
  for_each = var.enable_networking ? { for i, z in local.zones : z => i } : {}

  project_id    = var.project_id
  subnet_name   = "${var.vpc_name}-public-${each.key}"
  ip_cidr_range = local.public_cidrs[each.value]
  region        = var.region
  network       = module.vpc[0].id

  enable_flow_logs                = true
  log_config_aggregation_interval = var.log_config_aggregation_interval
  log_config_flow_sampling        = var.log_config_flow_sampling
}

# Private subnets (compute tier)
module "private_subnets" {
  source   = "../../network/subnet"
  for_each = var.enable_networking ? { for i, z in local.zones : z => i } : {}

  project_id    = var.project_id
  subnet_name   = "${var.vpc_name}-private-${each.key}"
  ip_cidr_range = local.private_cidrs[each.value]
  region        = var.region
  network       = module.vpc[0].id

  enable_flow_logs                = true
  log_config_aggregation_interval = var.log_config_aggregation_interval
  log_config_flow_sampling        = var.log_config_flow_sampling

  # Architecture: Enable Private Google Access for internal VMs
  private_ip_google_access = true

  # GKE Readiness: Pass secondary ranges if defined for this zone
  secondary_ip_ranges = try(var.secondary_ranges[each.key], [])
}

# Database subnets
module "database_subnets" {
  source   = "../../network/subnet"
  for_each = var.enable_networking ? { for i, z in local.zones : z => i } : {}

  project_id    = var.project_id
  subnet_name   = "${var.vpc_name}-db-${each.key}"
  ip_cidr_range = local.database_cidrs[each.value]
  region        = var.region
  network       = module.vpc[0].id

  enable_flow_logs                = true
  log_config_aggregation_interval = var.log_config_aggregation_interval
  log_config_flow_sampling        = var.log_config_flow_sampling

  # Architecture: Enable Private Google Access for secure data operations
  private_ip_google_access = true
}

# -----------------------------------------------------------------------------
# CORE SERVICES (NAT, PSA, PSC)
# -----------------------------------------------------------------------------

# Integrated NAT Gateway (for private/db subnets).
# The for expressions in `subnetworks` reference module.private_subnets and
# module.database_subnets outputs — Terraform resolves these as implicit
# dependencies and will not plan this NAT before subnet self-links are known.
# No explicit depends_on is needed here.
module "integrated_nat" {
  source = "../../network/nat"
  count  = var.enable_networking && var.enable_cloud_nat ? 1 : 0

  project_id = var.project_id
  name       = "${var.vpc_name}-nat"
  region     = var.region
  network    = module.vpc[0].id

  create_router = true
  router_name   = "${var.vpc_name}-router"

  nat_ip_allocate_option             = var.integrated_nat_ip_allocate_option
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetworks = concat(
    [for s in module.private_subnets : { name = s.self_link, source_ip_ranges_to_nat = ["ALL_IP_RANGES"] }],
    [for s in module.database_subnets : { name = s.self_link, source_ip_ranges_to_nat = ["ALL_IP_RANGES"] }]
  )

  enable_logging = true
  log_filter     = var.integrated_nat_log_filter
}

# Private Service Access (for Cloud SQL, Redis, etc.)
module "private_service_access" {
  source = "../../network/private-service-access"
  count  = var.enable_networking && var.enable_private_service_access ? 1 : 0

  project_id    = var.project_id
  vpc_network   = module.vpc[0].id
  name          = var.psa_name
  prefix_length = var.psa_prefix_length
}

# Private Service Connect (for Google APIs)
module "private_service_connect" {
  source = "../../network/private-service-connect"
  count  = var.enable_networking && var.enable_private_service_connect ? 1 : 0

  project_id = var.project_id
  name       = "${var.vpc_name}-psc"
  network    = module.vpc[0].id
  target     = var.psc_target
}

