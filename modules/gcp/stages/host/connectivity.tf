# Host stage: hybrid and inter-VPC connectivity (VPN, peering, standalone NAT, interconnect).
# Part of modules/gcp/stages/host.

# =============================================================================
# HYBRID CONNECTIVITY (VPN)
# =============================================================================

module "vpn" {
  source = "../../network/vpn"
  count  = var.enable_vpn ? 1 : 0

  project_id                = var.project_id
  name                      = "${var.project_prefix}-vpn"
  region                    = var.region
  network                   = var.enable_networking ? module.vpc[0].id : var.existing_network_id
  tunnel_count              = var.vpn_tunnel_count
  router_asn                = var.vpn_router_asn
  peer_asn                  = var.vpn_peer_asn
  peer_external_gateway_ips = var.vpn_peer_gateway_ips
  shared_secret             = var.vpn_shared_secret
  local_ip_addresses        = var.vpn_local_ips
  peer_ip_addresses         = var.vpn_peer_ips
  advertised_ip_ranges      = var.vpn_advertised_ip_ranges
  labels                    = var.labels
}

# =============================================================================
# VPC PEERING (Hub-and-Spoke)
# =============================================================================

module "vpc_peering" {
  source   = "../../network/vpc-peering"
  for_each = var.vpc_peerings

  peering_name           = each.key
  network                = var.enable_networking ? module.vpc[0].self_link : var.existing_network_self_link
  peer_network           = each.value.peer_network
  create_reverse_peering = try(each.value.create_reverse_peering, true)
  export_custom_routes   = try(each.value.export_custom_routes, false)
  import_custom_routes   = try(each.value.import_custom_routes, false)
}

# =============================================================================
# STANDALONE NAT GATEWAY (when not using VPC-integrated NAT)
# =============================================================================

module "standalone_nat" {
  source   = "../../network/nat"
  for_each = var.standalone_nat_gateways

  project_id = var.project_id
  name       = each.key
  region     = each.value.region
  network    = var.enable_networking ? module.vpc[0].self_link : var.existing_network_self_link

  create_router                      = try(each.value.create_router, true)
  router_name                        = try(each.value.router_name, "${each.key}-router")
  nat_ip_allocate_option             = try(each.value.nat_ip_allocate_option, "AUTO_ONLY")
  nat_ips                            = try(each.value.nat_ips, [])
  source_subnetwork_ip_ranges_to_nat = try(each.value.source_subnetwork_ip_ranges_to_nat, "ALL_SUBNETWORKS_ALL_IP_RANGES")
  subnetworks                        = try(each.value.subnetworks, [])
  min_ports_per_vm                   = try(each.value.min_ports_per_vm, 64)
  enable_dynamic_port_allocation     = try(each.value.enable_dynamic_port_allocation, false)
  enable_logging                     = try(each.value.enable_logging, true)
  log_filter                         = try(each.value.log_filter, "ERRORS_ONLY")
}

# =============================================================================
# CLOUD INTERCONNECT
# =============================================================================

module "interconnects" {
  source   = "../../network/interconnect"
  for_each = var.interconnects

  project_id      = var.project_id
  region          = each.value.region
  network         = var.enable_networking ? module.vpc[0].self_link : var.existing_network_self_link
  attachment_name = each.key

  interconnect_type = try(each.value.interconnect_type, "PARTNER")
  router_name       = each.value.router_name
  router_asn        = try(each.value.router_asn, 64512)
  create_router     = try(each.value.create_router, true)

  # Dedicated interconnect
  interconnect_self_link = try(each.value.interconnect_self_link, null)
  vlan_tag               = try(each.value.vlan_tag, null)
  bandwidth              = try(each.value.bandwidth, "BPS_10G")

  # Partner interconnect
  edge_availability_domain = try(each.value.edge_availability_domain, "AVAILABILITY_DOMAIN_1")

  # Common settings
  mtu           = try(each.value.mtu, 1440)
  admin_enabled = try(each.value.admin_enabled, true)
  encryption    = try(each.value.encryption, "NONE")

  # BGP
  create_bgp_peer      = try(each.value.create_bgp_peer, true)
  interface_ip_range   = try(each.value.interface_ip_range, null)
  peer_ip_address      = try(each.value.peer_ip_address, null)
  peer_asn             = try(each.value.peer_asn, 65000)
  enable_bfd           = try(each.value.enable_bfd, false)
  advertised_ip_ranges = try(each.value.advertised_ip_ranges, [])
}

