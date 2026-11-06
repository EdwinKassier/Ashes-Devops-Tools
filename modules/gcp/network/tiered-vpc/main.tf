/**
 * Copyright 2023 Ashes
 *
 * Tiered VPC - shared network building block
 *
 * One custom-mode VPC with a three-tier zonal subnet layout (public, private,
 * database) and the baseline tier firewall rules. It is the common foundation
 * of the `stages/net-hub`, `stages/net-spoke` and `stages/dns-anchor`
 * compositions, and it reproduces the network core of the deprecated
 * `stages/host` module resource-for-resource (same names, same CIDR maths),
 * so callers can migrate onto it with `moved` blocks and no replacement.
 *
 * Zones are an explicit, required input: zone discovery stays with the
 * composing stage so the subnet `for_each` keys never depend on a data source
 * read inside this module.
 */

locals {
  # Network tags for tiered security
  network_tags = {
    api_gateway = "api-gateway"
    public      = "public"
    compute     = "compute"
    database    = "database"
  }

  # Per-tier CIDRs: explicit lists win, otherwise one /24 (for a /16) per zone
  # at offsets 0, 16 and 32. Identical to the stages/host derivation.
  public_cidrs   = length(var.subnet_cidrs.public) > 0 ? var.subnet_cidrs.public : [for i, z in var.zones : cidrsubnet(var.cidr_block, 8, i)]
  private_cidrs  = length(var.subnet_cidrs.private) > 0 ? var.subnet_cidrs.private : [for i, z in var.zones : cidrsubnet(var.cidr_block, 8, 16 + i)]
  database_cidrs = length(var.subnet_cidrs.database) > 0 ? var.subnet_cidrs.database : [for i, z in var.zones : cidrsubnet(var.cidr_block, 8, 32 + i)]

  zone_index = { for i, z in var.zones : z => i }
}

# Deletion protection guard for the VPC and subnet stack.
#
# Terraform's prevent_destroy meta-argument must be a static literal. This
# guard exists only when deletion_protection = true and carries a static
# prevent_destroy = true, so any plan that would remove it is blocked. To
# deprovision a protected stack deliberately, first run:
#   terraform state rm '<module_address>.terraform_data.deletion_protection_guard[0]'
resource "terraform_data" "deletion_protection_guard" {
  count = var.deletion_protection ? 1 : 0

  input = "${var.project_id}/${var.name}"

  lifecycle {
    prevent_destroy = true
  }
}

# Guard: each explicit CIDR list must cover every zone, otherwise the subnet
# for_each would index past the end of the list with a cryptic error.
resource "terraform_data" "subnet_cidr_count_guard" {
  lifecycle {
    precondition {
      condition = (
        length(var.subnet_cidrs.public) == 0 || length(var.subnet_cidrs.public) >= length(var.zones)
        ) && (
        length(var.subnet_cidrs.private) == 0 || length(var.subnet_cidrs.private) >= length(var.zones)
        ) && (
        length(var.subnet_cidrs.database) == 0 || length(var.subnet_cidrs.database) >= length(var.zones)
      )
      error_message = "Each non-empty subnet_cidrs list must have at least as many entries as zones. Detected ${length(var.zones)} zones; provided public=${length(var.subnet_cidrs.public)}, private=${length(var.subnet_cidrs.private)}, database=${length(var.subnet_cidrs.database)} CIDRs. Either add CIDRs or leave the list empty to use auto-generated values."
    }
  }
}

# =============================================================================
# VPC + THREE-TIER SUBNETS
# =============================================================================

module "vpc" {
  source = "../vpc"

  project_id = var.project_id
  vpc_name   = var.name

  enable_shared_vpc_host          = var.shared_vpc_host
  delete_default_routes_on_create = true
  enable_deletion_protection      = var.deletion_protection
}

module "public_subnets" {
  source   = "../subnet"
  for_each = local.zone_index

  project_id    = var.project_id
  subnet_name   = "${var.name}-public-${each.key}"
  ip_cidr_range = local.public_cidrs[each.value]
  region        = var.region
  network       = module.vpc.id

  enable_flow_logs                = true
  log_config_aggregation_interval = var.flow_logs.aggregation_interval
  log_config_flow_sampling        = var.flow_logs.sampling
}

# Compute tier: Private Google Access on, optional GKE secondary ranges.
module "private_subnets" {
  source   = "../subnet"
  for_each = local.zone_index

  project_id    = var.project_id
  subnet_name   = "${var.name}-private-${each.key}"
  ip_cidr_range = local.private_cidrs[each.value]
  region        = var.region
  network       = module.vpc.id

  enable_flow_logs                = true
  log_config_aggregation_interval = var.flow_logs.aggregation_interval
  log_config_flow_sampling        = var.flow_logs.sampling

  private_ip_google_access = true
  secondary_ip_ranges      = try(var.secondary_ranges[each.key], [])
}

module "database_subnets" {
  source   = "../subnet"
  for_each = local.zone_index

  project_id    = var.project_id
  subnet_name   = "${var.name}-db-${each.key}"
  ip_cidr_range = local.database_cidrs[each.value]
  region        = var.region
  network       = module.vpc.id

  enable_flow_logs                = true
  log_config_aggregation_interval = var.flow_logs.aggregation_interval
  log_config_flow_sampling        = var.flow_logs.sampling

  private_ip_google_access = true
}

# =============================================================================
# BASELINE TIER FIREWALL RULES
# =============================================================================

module "firewall_apigateway_to_public" {
  source = "../network-firewall"

  project_id         = var.project_id
  firewall_rule_name = "${var.name}-allow-apigw-public"
  network            = module.vpc.name
  description        = "Allow traffic from API Gateway to public tier"

  allow_rules = [
    {
      protocol = "tcp"
      ports    = ["443", "80"]
    }
  ]

  source_tags    = [local.network_tags.api_gateway]
  target_tags    = [local.network_tags.public]
  enable_logging = var.firewall.enable_logging
}

module "firewall_public_to_compute" {
  source = "../network-firewall"

  project_id         = var.project_id
  firewall_rule_name = "${var.name}-allow-public-compute"
  network            = module.vpc.name
  description        = "Allow traffic from public tier to compute tier"

  allow_rules = [
    {
      protocol = "tcp"
      ports    = var.firewall.compute_tier_ports
    }
  ]

  source_tags    = [local.network_tags.public]
  target_tags    = [local.network_tags.compute]
  enable_logging = var.firewall.enable_logging
}

module "firewall_compute_to_database" {
  source = "../network-firewall"

  project_id         = var.project_id
  firewall_rule_name = "${var.name}-allow-compute-db"
  network            = module.vpc.name
  description        = "Allow traffic from compute tier to database tier"

  allow_rules = [
    {
      protocol = "tcp"
      ports    = var.firewall.database_ports
    }
  ]

  source_tags    = [local.network_tags.compute]
  target_tags    = [local.network_tags.database]
  enable_logging = var.firewall.enable_logging
}

# IAP TCP forwarding range for SSH/RDP (no public SSH).
module "firewall_iap_ssh_rdp" {
  source = "../network-firewall"
  count  = var.firewall.enable_iap_access ? 1 : 0

  project_id         = var.project_id
  firewall_rule_name = "${var.name}-allow-iap-ssh-rdp"
  network            = module.vpc.name
  description        = "Allow SSH and RDP from Identity-Aware Proxy VIP"

  allow_rules = [
    {
      protocol = "tcp"
      ports    = ["22", "3389"]
    }
  ]

  source_ranges  = ["35.235.240.0/20"]
  enable_logging = var.firewall.enable_logging
}

# Google health-check probe ranges (required for load balancers).
module "firewall_health_checks" {
  source = "../network-firewall"

  project_id         = var.project_id
  firewall_rule_name = "${var.name}-allow-health-checks"
  network            = module.vpc.name
  description        = "Allow GCP health check probes for Load Balancers"

  allow_rules = [
    {
      protocol = "tcp"
    }
  ]

  source_ranges  = ["35.191.0.0/16", "130.211.0.0/22"]
  enable_logging = var.firewall.enable_logging
}

# Defense in depth: no direct egress from the database tier.
module "firewall_database_deny_egress" {
  source = "../network-firewall"

  project_id         = var.project_id
  firewall_rule_name = "${var.name}-deny-db-egress"
  network            = module.vpc.name
  description        = "Deny direct egress from database tier for security"
  priority           = 65534
  direction          = "EGRESS"

  deny_rules = [
    {
      protocol = "all"
    }
  ]

  target_tags    = [local.network_tags.database]
  enable_logging = var.firewall.enable_logging
}

# Lowest-priority catch-all ingress deny, logged.
module "firewall_deny_all" {
  source = "../network-firewall"

  project_id         = var.project_id
  firewall_rule_name = "${var.name}-deny-all-ingress"
  network            = module.vpc.name
  description        = "Deny all ingress traffic (lowest priority) and log it"
  priority           = 65535
  direction          = "INGRESS"

  deny_rules = [
    {
      protocol = "all"
    }
  ]

  source_ranges  = ["0.0.0.0/0"]
  enable_logging = var.firewall.enable_logging
}
