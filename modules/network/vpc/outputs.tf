/**
 * Copyright 2023 Ashes
 *
 * VPC Module - Outputs
 */

output "network" {
  value       = google_compute_network.vpc
  description = "The created VPC resource"
}

output "network_id" {
  value       = google_compute_network.vpc.id
  description = "The ID of the VPC"
}

output "network_self_link" {
  value       = google_compute_network.vpc.self_link
  description = "The URI of the VPC"
}

output "network_name" {
  value       = google_compute_network.vpc.name
  description = "The name of the VPC"
}

output "public_subnets" {
  value       = google_compute_subnetwork.public
  description = "The created public subnets"
}

output "private_subnets" {
  value       = google_compute_subnetwork.private
  description = "The created private subnets"
}

output "database_subnets" {
  value       = google_compute_subnetwork.database
  description = "The created database subnets"
}

output "nat_ip" {
  value       = google_compute_router_nat.nat.nat_ips
  description = "The NAT IP addresses"
}

output "router" {
  value       = google_compute_router.router
  description = "The created router resource"
} 