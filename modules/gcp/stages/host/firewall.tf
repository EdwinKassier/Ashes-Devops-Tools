# Host stage: all firewall rules (tiered, utility, additional, hierarchical).
# Part of modules/gcp/stages/host.

# =============================================================================
# TIERED SECURITY FIREWALL RULES (Three-Tier Architecture)
# =============================================================================

# Allow API Gateway to Public tier
module "firewall_apigateway_to_public" {
  source = "../../network/network-firewall"
  count  = var.enable_networking ? 1 : 0

  project_id         = var.project_id
  firewall_rule_name = "${var.vpc_name}-allow-apigw-public"
  network            = module.vpc[0].name
  description        = "Allow traffic from API Gateway to public tier"

  allow_rules = [
    {
      protocol = "tcp"
      ports    = ["443", "80"]
    }
  ]

  source_tags    = [local.network_tags.api_gateway]
  target_tags    = [local.network_tags.public]
  enable_logging = var.enable_firewall_logging
}

# Allow Public tier to Compute tier
module "firewall_public_to_compute" {
  source = "../../network/network-firewall"
  count  = var.enable_networking ? 1 : 0

  project_id         = var.project_id
  firewall_rule_name = "${var.vpc_name}-allow-public-compute"
  network            = module.vpc[0].name
  description        = "Allow traffic from public tier to compute tier"

  allow_rules = [
    {
      protocol = "tcp"
      ports    = var.compute_tier_ports
    }
  ]

  source_tags    = [local.network_tags.public]
  target_tags    = [local.network_tags.compute]
  enable_logging = var.enable_firewall_logging
}

# Allow Compute tier to Database tier
module "firewall_compute_to_database" {
  source = "../../network/network-firewall"
  count  = var.enable_networking ? 1 : 0

  project_id         = var.project_id
  firewall_rule_name = "${var.vpc_name}-allow-compute-db"
  network            = module.vpc[0].name
  description        = "Allow traffic from compute tier to database tier"

  allow_rules = [
    {
      protocol = "tcp"
      ports    = var.database_ports
    }
  ]

  source_tags    = [local.network_tags.compute]
  target_tags    = [local.network_tags.database]
  enable_logging = var.enable_firewall_logging
}

# =============================================================================
# UTILITY FIREWALL RULES
# =============================================================================

# Allow IAP access for secure SSH/RDP
module "firewall_iap_ssh_rdp" {
  source = "../../network/network-firewall"
  count  = var.enable_networking && var.enable_iap_access ? 1 : 0

  project_id         = var.project_id
  firewall_rule_name = "${var.vpc_name}-allow-iap-ssh-rdp"
  network            = module.vpc[0].name
  description        = "Allow SSH and RDP from Identity-Aware Proxy VIP"

  allow_rules = [
    {
      protocol = "tcp"
      ports    = ["22", "3389"]
    }
  ]

  source_ranges  = ["35.235.240.0/20"]
  enable_logging = var.enable_firewall_logging
}

# Allow GCP Health Checks (required for Load Balancers)
module "firewall_health_checks" {
  source = "../../network/network-firewall"
  count  = var.enable_networking ? 1 : 0

  project_id         = var.project_id
  firewall_rule_name = "${var.vpc_name}-allow-health-checks"
  network            = module.vpc[0].name
  description        = "Allow GCP health check probes for Load Balancers"

  allow_rules = [
    {
      protocol = "tcp"
    }
  ]

  source_ranges  = ["35.191.0.0/16", "130.211.0.0/22"]
  enable_logging = var.enable_firewall_logging
}

# Deny direct egress from database tier (defense in depth)
module "firewall_database_deny_egress" {
  source = "../../network/network-firewall"
  count  = var.enable_networking ? 1 : 0

  project_id         = var.project_id
  firewall_rule_name = "${var.vpc_name}-deny-db-egress"
  network            = module.vpc[0].name
  description        = "Deny direct egress from database tier for security"
  priority           = 65534
  direction          = "EGRESS"

  deny_rules = [
    {
      protocol = "all"
    }
  ]

  target_tags    = [local.network_tags.database]
  enable_logging = var.enable_firewall_logging
}

# Deny all other ingress traffic (Logging / Catch-all)
module "firewall_deny_all" {
  source = "../../network/network-firewall"
  count  = var.enable_networking ? 1 : 0

  project_id         = var.project_id
  firewall_rule_name = "${var.vpc_name}-deny-all-ingress"
  network            = module.vpc[0].name
  description        = "Deny all ingress traffic (lowest priority) and log it"
  priority           = 65535
  direction          = "INGRESS"

  deny_rules = [
    {
      protocol = "all"
    }
  ]

  source_ranges  = ["0.0.0.0/0"]
  enable_logging = var.enable_firewall_logging
}

# =============================================================================
# ADDITIONAL FIREWALL RULES (Standalone)
# =============================================================================

module "additional_firewall_rules" {
  source   = "../../network/network-firewall"
  for_each = var.additional_firewall_rules

  project_id         = var.project_id
  firewall_rule_name = each.key
  network            = var.enable_networking ? module.vpc[0].name : var.existing_network_name
  direction          = each.value.direction
  description        = each.value.description
  priority           = each.value.priority
  allow_rules        = try(each.value.allow_rules, [])
  deny_rules         = try(each.value.deny_rules, [])
  source_ranges      = try(each.value.source_ranges, null)
  target_tags        = try(each.value.target_tags, null)
  source_tags        = try(each.value.source_tags, null)
  enable_logging     = var.enable_firewall_logging
}

# =============================================================================
# HIERARCHICAL FIREWALL POLICIES
# =============================================================================

module "hierarchical_firewall_policies" {
  source   = "../../network/hierarchical-firewall"
  for_each = var.hierarchical_firewall_policies

  parent         = each.value.parent
  policy_name    = each.key
  description    = try(each.value.description, "Managed by Terraform")
  rules          = try(each.value.rules, [])
  associations   = try(each.value.associations, [])
  enable_logging = try(each.value.enable_logging, true)
}
