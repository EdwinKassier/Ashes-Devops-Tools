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
  # The google provider deprecates numeric_id (network_id carries the same
  # number); filtering it out keeps the warning off every caller's plan.
  value       = { for k, v in google_compute_network.vpc : k => v if k != "numeric_id" }
  description = "The created VPC resource (every attribute except the provider-deprecated numeric_id; read network.network_id instead)"
}
