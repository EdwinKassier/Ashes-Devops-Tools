/**
 * Copyright 2023 Ashes
 *
 * VPC Module - Outputs
 */

output "id" {
  value       = google_compute_network.vpc.id
  description = "The ID of the VPC"
}

output "network_id" {
  description = "Deprecated alias for the VPC ID"
  value       = google_compute_network.vpc.id
}

output "self_link" {
  value       = google_compute_network.vpc.self_link
  description = "The URI of the VPC"
}

output "network_self_link" {
  description = "Deprecated alias for the VPC self link"
  value       = google_compute_network.vpc.self_link
}

output "name" {
  value       = google_compute_network.vpc.name
  description = "The name of the VPC"
}

output "network_name" {
  description = "Deprecated alias for the VPC name"
  value       = google_compute_network.vpc.name
}

output "network" {
  value       = google_compute_network.vpc
  description = "The created VPC resource"
}
