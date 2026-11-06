/**
 * Copyright 2023 Ashes
 *
 * net-hub - hub network composition
 *
 * The landing-zone hub: a Shared VPC host network with a three-tier VPC
 * (network/tiered-vpc), Cloud NAT, Private Service Access, Private Service
 * Connect, hierarchical (folder or org) firewall policies, the hub VPC-SC
 * perimeter, and opt-in hybrid connectivity (HA VPN, Cloud Interconnect).
 *
 * Replaces the hub use of the deprecated stages/host module (see the README
 * migration table for the moved blocks).
 */

locals {
  # Explicit zones win; otherwise fall back to the zones GCP returns.
  zones = length(var.network.explicit_zones) > 0 ? var.network.explicit_zones : data.google_compute_zones.available.names
}

# Auto-discover available zones (used only when network.explicit_zones is empty).
data "google_compute_zones" "available" {
  project = var.project_id
  region  = var.region

  lifecycle {
    postcondition {
      condition     = length(self.names) > 0
      error_message = "No compute zones returned for region '${var.region}' in project '${var.project_id}'. Verify the region is valid and the Compute Engine API is enabled."
    }
  }
}

# =============================================================================
# NETWORK CORE (VPC, three-tier subnets, baseline firewall)
# =============================================================================

module "network" {
  source = "../../network/tiered-vpc"

  project_id          = var.project_id
  name                = var.network.name
  region              = var.region
  cidr_block          = var.network.cidr_block
  zones               = local.zones
  subnet_cidrs        = var.network.subnet_cidrs
  secondary_ranges    = var.network.secondary_ranges
  shared_vpc_host     = var.network.shared_vpc_host
  deletion_protection = var.deletion_protection
  flow_logs           = var.network.flow_logs
  firewall            = var.firewall
}

# Folder- or organization-level firewall policies owned by the hub.
module "hierarchical_firewall_policies" {
  source   = "../../network/hierarchical-firewall"
  for_each = var.hierarchical_firewall_policies

  parent         = each.value.parent
  policy_name    = each.key
  description    = each.value.description
  rules          = each.value.rules
  associations   = each.value.associations
  enable_logging = each.value.enable_logging
}

# =============================================================================
# EGRESS AND PRIVATE SERVICES (NAT, PSA, PSC)
# =============================================================================

# Cloud NAT for the private and database tiers only (public tier excluded).
module "integrated_nat" {
  source = "../../network/nat"
  count  = var.nat.enabled ? 1 : 0

  project_id = var.project_id
  name       = "${var.network.name}-nat"
  region     = var.region
  network    = module.network.network_id

  create_router = true
  router_name   = "${var.network.name}-router"

  nat_ip_allocate_option             = var.nat.ip_allocate_option
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetworks = concat(
    [for s in module.network.subnets.private : { name = s.self_link, source_ip_ranges_to_nat = ["ALL_IP_RANGES"] }],
    [for s in module.network.subnets.database : { name = s.self_link, source_ip_ranges_to_nat = ["ALL_IP_RANGES"] }]
  )

  enable_logging = true
  log_filter     = var.nat.log_filter
}

module "private_service_access" {
  source = "../../network/private-service-access"
  count  = var.private_service_access.enabled ? 1 : 0

  project_id    = var.project_id
  vpc_network   = module.network.network_id
  name          = var.private_service_access.name
  prefix_length = var.private_service_access.prefix_length
}

module "private_service_connect" {
  source = "../../network/private-service-connect"
  count  = var.private_service_connect.enabled ? 1 : 0

  project_id = var.project_id
  name       = "${var.network.name}-psc"
  network    = module.network.network_id
  target     = var.private_service_connect.target
}

# =============================================================================
# HYBRID CONNECTIVITY (HA VPN, Cloud Interconnect), opt-in
# =============================================================================

module "vpn" {
  source = "../../network/vpn"
  count  = var.vpn.enabled ? 1 : 0

  project_id                = var.project_id
  name                      = "${var.project_prefix}-vpn"
  region                    = var.region
  network                   = module.network.network_id
  tunnel_count              = var.vpn.tunnel_count
  router_asn                = var.vpn.router_asn
  peer_asn                  = var.vpn.peer_asn
  peer_external_gateway_ips = var.vpn.peer_gateway_ips
  shared_secret             = var.vpn_shared_secret
  local_ip_addresses        = var.vpn.local_ips
  peer_ip_addresses         = var.vpn.peer_ips
  advertised_ip_ranges      = var.vpn.advertised_ip_ranges
  labels                    = var.labels
}

module "interconnects" {
  source   = "../../network/interconnect"
  for_each = var.interconnects

  project_id      = var.project_id
  region          = each.value.region
  network         = module.network.network_self_link
  attachment_name = each.key

  interconnect_type = each.value.interconnect_type
  router_name       = each.value.router_name
  router_asn        = each.value.router_asn
  create_router     = each.value.create_router

  interconnect_self_link   = each.value.interconnect_self_link
  vlan_tag                 = each.value.vlan_tag
  bandwidth                = each.value.bandwidth
  edge_availability_domain = each.value.edge_availability_domain

  mtu           = each.value.mtu
  admin_enabled = each.value.admin_enabled
  encryption    = each.value.encryption

  create_bgp_peer      = each.value.create_bgp_peer
  interface_ip_range   = each.value.interface_ip_range
  peer_ip_address      = each.value.peer_ip_address
  peer_asn             = each.value.peer_asn
  enable_bfd           = each.value.enable_bfd
  advertised_ip_ranges = each.value.advertised_ip_ranges
}

# =============================================================================
# VPC SERVICE CONTROLS (hub perimeter)
# =============================================================================

module "vpc_service_controls" {
  source   = "../../network/vpc-sc"
  for_each = var.vpc_service_controls

  organization_id            = each.value.organization_id
  access_policy_name         = each.value.access_policy_name
  create_access_policy       = each.value.create_access_policy
  perimeter_name             = each.key
  perimeter_title            = each.value.perimeter_title
  description                = each.value.description
  perimeter_type             = each.value.perimeter_type
  protected_projects         = each.value.protected_projects
  restricted_services        = each.value.restricted_services
  access_levels              = each.value.access_levels
  ingress_policies           = each.value.ingress_policies
  egress_policies            = each.value.egress_policies
  enable_dry_run             = each.value.enable_dry_run
  enable_deletion_protection = each.value.enable_deletion_protection

  dry_run_restricted_services = each.value.dry_run_restricted_services
  dry_run_ingress_policies    = each.value.dry_run_ingress_policies
  dry_run_egress_policies     = each.value.dry_run_egress_policies
}
