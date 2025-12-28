/**
 * Copyright 2023 Ashes
 *
 * Cloud NAT Module - Outputs
 */

# Standard interface outputs
output "id" {
  description = "The ID of the NAT gateway"
  value       = google_compute_router_nat.nat.id
}

output "self_link" {
  description = "The self_link of the NAT gateway (same as id for this resource)"
  value       = google_compute_router_nat.nat.id
}

output "name" {
  description = "The name of the NAT gateway"
  value       = google_compute_router_nat.nat.name
}

# NAT-specific outputs
output "nat" {
  description = "The NAT gateway resource"
  value       = google_compute_router_nat.nat
}

output "nat_ips" {
  description = "The list of external IP addresses used for NAT"
  value       = google_compute_router_nat.nat.nat_ips
}

output "router" {
  description = "The Cloud Router resource (if created)"
  value       = var.create_router ? google_compute_router.router[0] : null
}

output "router_name" {
  description = "The name of the Cloud Router"
  value       = local.router_name
}

output "region" {
  description = "The region of the NAT gateway"
  value       = var.region
}
