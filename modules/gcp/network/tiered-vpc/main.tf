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

  # firewall_mode: legacy = tag-based VPC rules only; both = VPC rules plus the
  # network firewall policy (migration step); policy = network firewall policy only.
  create_vpc_rules       = var.firewall_mode != "policy"
  create_firewall_policy = var.firewall_mode != "legacy"

  # New policy-mode networks evaluate the policy before VPC rules. legacy and
  # both leave the order unset (API default AFTER_CLASSIC_FIREWALL), so legacy
  # rules keep deciding while both are present. An explicit value always wins.
  firewall_policy_enforcement_order = coalesce(
    var.firewall_policy_enforcement_order,
    var.firewall_mode == "policy" ? "BEFORE_CLASSIC_FIREWALL" : "UNSET",
  )
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

  network_firewall_policy_enforcement_order = local.firewall_policy_enforcement_order == "UNSET" ? null : local.firewall_policy_enforcement_order
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
# BASELINE TIER FIREWALL RULES (tag-based VPC rules; firewall_mode legacy / both)
# =============================================================================
#
# Each call has count = 0 in firewall_mode = "policy". The moved blocks below
# carry pre-count state (unkeyed addresses) onto [0], so turning count on is a
# no-op for existing networks. firewall_iap_ssh_rdp was already counted.

moved {
  from = module.firewall_apigateway_to_public
  to   = module.firewall_apigateway_to_public[0]
}

moved {
  from = module.firewall_public_to_compute
  to   = module.firewall_public_to_compute[0]
}

moved {
  from = module.firewall_compute_to_database
  to   = module.firewall_compute_to_database[0]
}

moved {
  from = module.firewall_health_checks
  to   = module.firewall_health_checks[0]
}

moved {
  from = module.firewall_database_deny_egress
  to   = module.firewall_database_deny_egress[0]
}

moved {
  from = module.firewall_deny_all
  to   = module.firewall_deny_all[0]
}

module "firewall_apigateway_to_public" {
  source = "../network-firewall"
  count  = local.create_vpc_rules ? 1 : 0

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
  count  = local.create_vpc_rules ? 1 : 0

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
  count  = local.create_vpc_rules ? 1 : 0

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
  count  = local.create_vpc_rules && var.firewall.enable_iap_access ? 1 : 0

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
  count  = local.create_vpc_rules ? 1 : 0

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
  count  = local.create_vpc_rules ? 1 : 0

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
  count  = local.create_vpc_rules ? 1 : 0

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

# =============================================================================
# NETWORK FIREWALL POLICY (firewall_mode both / policy)
# =============================================================================
#
# One global network firewall policy and one association per VPC (a VPC takes
# only one). Rules mirror the tag-based baseline above but select tiers by
# subnet CIDR (src_ip_ranges / dest_ip_ranges), so a principal that can set
# network tags on an instance cannot move it into a more trusted tier.
#
# There is deliberately no trailing deny-all: traffic no policy rule matches
# goes to the next stage (VPC rules, then the implied deny), so GKE's
# automatic VPC firewall rules keep working.
#
# Priorities are fixed per rule key in the reserved 64000-64999 block, so they
# are unique and stable whichever optional rules are enabled. Other modules
# that add rules to this policy (e.g. network/internal-lb) must stay outside it.

locals {
  firewall_policy_rules_all = {
    "apigateway-to-public" = {
      enabled                 = length(var.firewall.api_gateway_source_ranges) > 0
      priority                = 64000
      description             = "Allow traffic from API Gateway to public tier"
      direction               = "INGRESS"
      action                  = "allow"
      src_ip_ranges           = var.firewall.api_gateway_source_ranges
      dest_ip_ranges          = local.public_cidrs
      ip_protocol             = "tcp"
      ports                   = ["443", "80"]
      target_service_accounts = null
    }
    "public-to-compute" = {
      enabled                 = true
      priority                = 64010
      description             = "Allow traffic from public tier to compute tier"
      direction               = "INGRESS"
      action                  = "allow"
      src_ip_ranges           = local.public_cidrs
      dest_ip_ranges          = local.private_cidrs
      ip_protocol             = "tcp"
      ports                   = var.firewall.compute_tier_ports
      target_service_accounts = null
    }
    "compute-to-database" = {
      enabled                 = true
      priority                = 64020
      description             = "Allow traffic from compute tier to database tier"
      direction               = "INGRESS"
      action                  = "allow"
      src_ip_ranges           = local.private_cidrs
      dest_ip_ranges          = local.database_cidrs
      ip_protocol             = "tcp"
      ports                   = var.firewall.database_ports
      target_service_accounts = null
    }
    "iap-ssh-rdp" = {
      enabled                 = var.firewall.enable_iap_access
      priority                = 64030
      description             = "Allow SSH and RDP from Identity-Aware Proxy VIP"
      direction               = "INGRESS"
      action                  = "allow"
      src_ip_ranges           = ["35.235.240.0/20"]
      dest_ip_ranges          = null
      ip_protocol             = "tcp"
      ports                   = ["22", "3389"]
      target_service_accounts = null
    }
    "health-checks" = {
      enabled                 = true
      priority                = 64040
      description             = "Allow GCP health check probes for Load Balancers"
      direction               = "INGRESS"
      action                  = "allow"
      src_ip_ranges           = ["35.191.0.0/16", "130.211.0.0/22"]
      dest_ip_ranges          = null
      ip_protocol             = "tcp"
      ports                   = null
      target_service_accounts = null
    }
    "database-deny-egress" = {
      enabled                 = true
      priority                = 64900
      description             = "Deny direct egress from database tier for security"
      direction               = "EGRESS"
      action                  = "deny"
      src_ip_ranges           = local.database_cidrs
      dest_ip_ranges          = ["0.0.0.0/0"]
      ip_protocol             = "all"
      ports                   = null
      target_service_accounts = length(var.firewall.database_egress_target_service_accounts) > 0 ? var.firewall.database_egress_target_service_accounts : null
    }
  }

  firewall_policy_rules = {
    for k, r in local.firewall_policy_rules_all : k => r if r.enabled && local.create_firewall_policy
  }
}

# Terraform cannot read the previous firewall_mode, so it cannot tell a
# greenfield policy network from one moving off `both`. This check warns
# whenever policy mode derives the enforcement order implicitly: moving from
# `both` with the override unset would delete the legacy rules AND flip the
# order to BEFORE_CLASSIC_FIREWALL in one apply. Setting the order explicitly
# silences it.
check "firewall_policy_enforcement_order_explicit" {
  assert {
    condition     = var.firewall_mode != "policy" || var.firewall_policy_enforcement_order != null
    error_message = "firewall_mode = \"policy\" with firewall_policy_enforcement_order unset derives BEFORE_CLASSIC_FIREWALL. If this network is moving from \"both\", this one apply both deletes the legacy VPC rules and flips the enforcement order. Set firewall_policy_enforcement_order explicitly: AFTER_CLASSIC_FIREWALL for runbook step 3, BEFORE_CLASSIC_FIREWALL for step 4 (docs/runbooks/gcp-firewall-policy-migration.md)."
  }
}

resource "google_compute_network_firewall_policy" "tier" {
  count = local.create_firewall_policy ? 1 : 0

  project     = var.project_id
  name        = "${var.name}-tier-policy"
  description = "Baseline tier firewall policy for ${var.name} (tiers selected by subnet CIDR)"
}

resource "google_compute_network_firewall_policy_association" "tier" {
  count = local.create_firewall_policy ? 1 : 0

  project           = var.project_id
  name              = "${var.name}-tier-policy"
  attachment_target = module.vpc.id
  firewall_policy   = google_compute_network_firewall_policy.tier[0].name
}

resource "google_compute_network_firewall_policy_rule" "tier" {
  for_each = local.firewall_policy_rules

  project         = var.project_id
  firewall_policy = google_compute_network_firewall_policy.tier[0].name
  rule_name       = "${var.name}-${each.key}"
  description     = each.value.description
  priority        = each.value.priority
  direction       = each.value.direction
  action          = each.value.action
  enable_logging  = var.firewall.enable_logging

  # Egress only: ingress rules select their target tier by dest_ip_ranges.
  target_service_accounts = each.value.direction == "EGRESS" ? each.value.target_service_accounts : null

  match {
    src_ip_ranges  = each.value.src_ip_ranges
    dest_ip_ranges = each.value.dest_ip_ranges

    layer4_configs {
      ip_protocol = each.value.ip_protocol
      ports       = each.value.ports
    }
  }
}
