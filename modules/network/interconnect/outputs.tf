/**
 * Copyright 2023 Ashes
 *
 * Cloud Interconnect Module - Outputs
 */

# Standard interface outputs
output "id" {
  description = "The ID of the interconnect attachment"
  value       = local.attachment != null ? local.attachment.id : null
}

output "self_link" {
  description = "The self_link of the interconnect attachment"
  value       = local.attachment != null ? local.attachment.self_link : null
}

output "name" {
  description = "The name of the interconnect attachment"
  value       = local.attachment != null ? local.attachment.name : null
}

output "attachment" {
  description = "The full interconnect attachment resource"
  value       = local.attachment
}

output "router" {
  description = "The Cloud Router resource (if created)"
  value       = var.create_router ? google_compute_router.router[0] : null
}

output "router_name" {
  description = "The name of the Cloud Router"
  value       = local.router_name
}

output "interface" {
  description = "The router interface resource"
  value       = length(google_compute_router_interface.interface) > 0 ? google_compute_router_interface.interface[0] : null
}

output "bgp_peer" {
  description = "The BGP peer resource"
  value       = length(google_compute_router_peer.peer) > 0 ? google_compute_router_peer.peer[0] : null
}

output "pairing_key" {
  description = "The pairing key for partner interconnect (share with partner provider)"
  value = var.interconnect_type == "PARTNER" && local.attachment != null ? (
    local.attachment.pairing_key
  ) : null
  sensitive = true
}

output "cloud_router_ip_address" {
  description = "The Cloud Router's IP address on this interconnect"
  value       = local.attachment != null ? local.attachment.cloud_router_ip_address : null
}

output "customer_router_ip_address" {
  description = "The customer router's IP address"
  value       = local.attachment != null ? local.attachment.customer_router_ip_address : null
}

output "state" {
  description = "Current state of the interconnect attachment"
  value       = local.attachment != null ? local.attachment.state : null
}

output "operational_status" {
  description = "Operational status of the interconnect attachment"
  value = var.interconnect_type == "PARTNER" && local.attachment != null ? (
    local.attachment.partner_metadata != null ? "Partner metadata available" : "Awaiting partner activation"
    ) : (
    local.attachment != null ? local.attachment.state : null
  )
}
