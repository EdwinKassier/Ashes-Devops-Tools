/**
 * Copyright 2023 Ashes
 *
 * net-hub - hub network composition
 *
 * The landing-zone hub: a Shared VPC host network with a three-tier VPC
 * (network/tiered-vpc), Cloud NAT, Private Service Access, Private Service
 * Connect, hierarchical (folder or org) firewall policies, the hub VPC-SC
 * perimeter, opt-in hybrid connectivity (HA VPN, Cloud Interconnect) and an
 * opt-in Network Connectivity Center hub (the alternative to spoke peering).
 *
 * Opt-in additional_regions add regional subnets (and a Cloud Router and NAT
 * per region) to the same VPC; empty keeps the single-region layout.
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
  additional_regions  = var.additional_regions

  # Cloud NAT needs a route to the default internet gateway (tiered-vpc deletes it).
  enable_internet_egress_route = var.nat.enabled

  firewall_mode                     = var.firewall_mode
  firewall_policy_enforcement_order = var.firewall_policy_enforcement_order
  firewall                          = var.firewall
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

# Cloud NAT for the private tier (public tier excluded). The database tier is
# NATed only with nat.include_database_subnets: its egress deny is tag-based,
# so an untagged VM there would otherwise reach the internet.
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
    var.nat.include_database_subnets ? [for s in module.network.subnets.database : { name = s.self_link, source_ip_ranges_to_nat = ["ALL_IP_RANGES"] }] : []
  )

  enable_logging = true
  log_filter     = var.nat.log_filter
}

# One Cloud Router and Cloud NAT per additional region with nat = true, same
# settings as the primary. Separate block keyed by region: the primary
# integrated_nat[0] address is unchanged.
module "additional_region_nat" {
  source   = "../../network/nat"
  for_each = var.nat.enabled ? { for region, r in var.additional_regions : region => r if r.nat } : {}

  project_id = var.project_id
  name       = "${var.network.name}-nat-${each.key}"
  region     = each.key
  network    = module.network.network_id

  create_router = true
  router_name   = "${var.network.name}-router-${each.key}"

  nat_ip_allocate_option             = var.nat.ip_allocate_option
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetworks = concat(
    [{ name = module.network.additional_region_subnets[each.key].private.self_link, source_ip_ranges_to_nat = ["ALL_IP_RANGES"] }],
    var.nat.include_database_subnets ? [{ name = module.network.additional_region_subnets[each.key].database.self_link, source_ip_ranges_to_nat = ["ALL_IP_RANGES"] }] : [],
  )

  enable_logging = true
  log_filter     = var.nat.log_filter
}

# Central egress control (opt-in, preview): Secure Web Proxy with an FQDN
# allowlist, optionally published to the spokes over Private Service Connect.
module "secure_web_proxy" {
  source = "../../network/secure-web-proxy"
  count  = var.secure_web_proxy.enabled ? 1 : 0

  project_id = var.project_id
  name       = "${trimsuffix(substr(var.network.name, 0, 36), "-")}-swp"
  region     = var.region
  network    = module.network.network_id
  subnetwork = module.network.subnets.private[sort(keys(module.network.subnets.private))[0]].id

  address          = var.secure_web_proxy.address
  ports            = var.secure_web_proxy.ports
  allowed_fqdns    = var.secure_web_proxy.allowed_fqdns
  additional_rules = var.secure_web_proxy.additional_rules
  certificate_urls = var.secure_web_proxy.certificate_urls

  create_proxy_only_subnet = var.secure_web_proxy.proxy_only_subnet_cidr != null
  proxy_only_subnet_cidr   = var.secure_web_proxy.proxy_only_subnet_cidr

  create_service_attachment = var.secure_web_proxy.psc_nat_subnet_cidr != null
  psc_nat_subnet_cidr       = var.secure_web_proxy.psc_nat_subnet_cidr
  consumer_accept_projects  = var.secure_web_proxy.consumer_accept_projects

  labels = var.labels
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
  shared_secret_wo          = var.vpn_shared_secret_wo
  shared_secret_wo_version  = var.vpn_shared_secret_wo_version
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
# NETWORK CONNECTIVITY CENTER (opt-in alternative to hub-and-spoke peering)
# =============================================================================

# The hub, and the hub VPC as its center-group spoke (default group on MESH).
# Environment spokes join the edge group from stages/net-spoke (connectivity =
# ncc). The hub VPC can join while environment VPCs are still peered with it;
# each environment VPC must drop its peering before it becomes a spoke
# (docs/runbooks/gcp-peering-to-ncc-migration.md).
module "ncc_hub" {
  source = "../../network/ncc-hub"
  count  = var.ncc.enabled ? 1 : 0

  project_id      = var.project_id
  name            = coalesce(var.ncc.name, "${var.project_prefix}-ncc-hub")
  description     = "Landing-zone NCC hub for ${var.project_prefix}"
  preset_topology = var.ncc.preset_topology
  export_psc      = var.ncc.export_psc
  labels          = var.labels

  auto_accept_projects = var.ncc.auto_accept_projects
}

module "ncc_hub_spoke" {
  source = "../../network/ncc-spoke"
  count  = var.ncc.enabled ? 1 : 0

  project_id  = var.project_id
  name        = var.network.name
  description = "NCC center spoke for the hub VPC ${var.network.name}"
  labels      = var.labels
  hub_id      = module.ncc_hub[0].id
  group       = module.ncc_hub[0].center_group

  linked_vpc_network = {
    uri = module.network.network_self_link
  }

  producer_vpc_networks = var.private_service_access.enabled && var.ncc.export_private_service_access ? {
    psa = {
      network = module.network.network_name
      peering = module.private_service_access[0].peering.peering
    }
  } : {}
}

# Under NCC the hub's HA VPN tunnels become a hybrid spoke, so on-premises
# routes reach the other spokes through the hub instead of only the hub VPC.
locals {
  ncc_vpn_spoke_group = var.ncc.enabled ? module.ncc_hub[0].center_group : null
}

module "ncc_vpn_spoke" {
  source = "../../network/ncc-spoke"
  count  = var.ncc.enabled && var.vpn.enabled ? 1 : 0

  project_id  = var.project_id
  name        = "${var.project_prefix}-vpn"
  description = "NCC hybrid spoke for the hub HA VPN tunnels"
  labels      = var.labels
  hub_id      = module.ncc_hub[0].id
  # Hybrid spokes join the CENTER group (default on MESH): on a STAR hub, edge
  # spokes reach only the center, so on-premises would otherwise see just the
  # hub VPC and not the environment spokes.
  group    = local.ncc_vpn_spoke_group
  location = var.region

  linked_vpn_tunnels = {
    uris                       = module.vpn[0].tunnel_self_links
    site_to_site_data_transfer = var.ncc.vpn_site_to_site_data_transfer
  }
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

# =============================================================================
# DATA-PLANE ALERTS (on for the features that exist)
# =============================================================================

locals {
  alert_vpn  = var.vpn.enabled
  alert_bgp  = var.vpn.enabled || length(var.interconnects) > 0
  alert_nat  = var.nat.enabled
  any_alerts = var.alerting.enabled && (local.alert_vpn || local.alert_bgp || local.alert_nat)
}

module "network_alerts" {
  source = "../../monitoring/alert-policy"
  count  = local.any_alerts ? 1 : 0

  project_id                     = var.project_id
  alert_display_name_prefix      = var.network.name
  extra_notification_channel_ids = var.alerting.notification_channel_ids

  # Only the network data-plane policies; the compute and Cloud Run ones
  # belong to the workloads.
  enable_high_cpu_alert     = false
  enable_high_memory_alert  = false
  enable_error_rate_alert   = false
  enable_high_latency_alert = false

  enable_vpn_tunnel_alert             = local.alert_vpn
  enable_bgp_session_alert            = local.alert_bgp
  enable_nat_allocation_failure_alert = local.alert_nat
  enable_nat_dropped_packets_alert    = local.alert_nat
  nat_dropped_packets_threshold       = var.alerting.nat_dropped_packets_threshold
}
