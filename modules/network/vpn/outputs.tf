/**
 * Copyright 2023 Ashes
 *
 * Cloud VPN Module - Outputs
 */

output "gateway" {
  description = "The HA VPN gateway resource"
  value       = google_compute_ha_vpn_gateway.gateway
}

output "id" {
  description = "The ID of the VPN gateway"
  value       = google_compute_ha_vpn_gateway.gateway.id
}

output "self_link" {
  description = "The URI of the VPN gateway"
  value       = google_compute_ha_vpn_gateway.gateway.self_link
}

output "gateway_ip_addresses" {
  description = "The external IP addresses of the VPN gateway interfaces"
  value       = google_compute_ha_vpn_gateway.gateway.vpn_interfaces[*].ip_address
}

output "tunnels" {
  description = "The VPN tunnel resources"
  value       = google_compute_vpn_tunnel.tunnels
}

output "tunnel_statuses" {
  description = "The status of each VPN tunnel"
  value       = google_compute_vpn_tunnel.tunnels[*].detailed_status
}

output "router" {
  description = "The Cloud Router resource"
  value       = google_compute_router.router
}

output "bgp_peers" {
  description = "The BGP peer resources"
  value       = google_compute_router_peer.peers
}
