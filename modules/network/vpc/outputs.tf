/**
 * Copyright 2023 Ashes
 *
 * VPC Module - Outputs
 */

output "id" {
  value       = google_compute_network.vpc.id
  description = "The ID of the VPC"
}

output "self_link" {
  value       = google_compute_network.vpc.self_link
  description = "The URI of the VPC"
}

output "name" {
  value       = google_compute_network.vpc.name
  description = "The name of the VPC"
}

output "network" {
  value       = google_compute_network.vpc
  description = "The created VPC resource"
}