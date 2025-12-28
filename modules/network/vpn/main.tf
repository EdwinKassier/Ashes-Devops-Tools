/**
 * Copyright 2023 Ashes
 *
 * Cloud VPN Module - Main Configuration
 * 
 * Creates an HA VPN gateway with BGP routing for hybrid connectivity.
 */

locals {
  router_name = coalesce(var.router_name, "${var.name}-router")
}

# HA VPN Gateway
resource "google_compute_ha_vpn_gateway" "gateway" {
  project = var.project_id
  name    = "${var.name}-ha-gateway"
  network = var.network
  region  = var.region

  lifecycle {
    prevent_destroy = false # Set to true for production usage
  }
}

# External VPN Gateway (peer)
resource "google_compute_external_vpn_gateway" "peer" {
  project         = var.project_id
  name            = "${var.name}-peer-gateway"
  redundancy_type = var.tunnel_count == 2 ? "TWO_IPS_REDUNDANCY" : "SINGLE_IP_INTERNALLY_REDUNDANT"

  dynamic "interface" {
    for_each = range(var.tunnel_count)
    content {
      id         = interface.value
      ip_address = var.peer_external_gateway_ip
    }
  }
}

# Cloud Router for BGP
resource "google_compute_router" "router" {
  project = var.project_id
  name    = local.router_name
  network = var.network
  region  = var.region

  bgp {
    asn            = var.router_asn
    advertise_mode = length(var.advertised_ip_ranges) > 0 ? "CUSTOM" : "DEFAULT"

    dynamic "advertised_ip_ranges" {
      for_each = var.advertised_ip_ranges
      content {
        range       = advertised_ip_ranges.value.range
        description = advertised_ip_ranges.value.description
      }
    }
  }
}

# VPN Tunnels
resource "google_compute_vpn_tunnel" "tunnels" {
  count = var.tunnel_count

  project                         = var.project_id
  name                            = "${var.name}-tunnel-${count.index}"
  region                          = var.region
  vpn_gateway                     = google_compute_ha_vpn_gateway.gateway.id
  vpn_gateway_interface           = count.index
  peer_external_gateway           = google_compute_external_vpn_gateway.peer.id
  peer_external_gateway_interface = count.index
  shared_secret                   = var.shared_secret
  router                          = google_compute_router.router.id
  ike_version                     = 2

  labels = var.labels
}

# Router Interfaces
resource "google_compute_router_interface" "interfaces" {
  count = var.tunnel_count

  project    = var.project_id
  name       = "${var.name}-interface-${count.index}"
  router     = google_compute_router.router.name
  region     = var.region
  ip_range   = "${var.local_ip_addresses[count.index]}/30"
  vpn_tunnel = google_compute_vpn_tunnel.tunnels[count.index].name
}

# BGP Peers
resource "google_compute_router_peer" "peers" {
  count = var.tunnel_count

  project                   = var.project_id
  name                      = "${var.name}-peer-${count.index}"
  router                    = google_compute_router.router.name
  region                    = var.region
  peer_ip_address           = var.peer_ip_addresses[count.index]
  peer_asn                  = var.peer_asn
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.interfaces[count.index].name
}
