/**
 * Copyright 2023 Ashes
 *
 * VPC Peering Module - Outputs
 */

output "peering" {
  description = "The primary peering connection resource"
  value       = google_compute_network_peering.peering
}

output "id" {
  description = "The ID of the peering connection"
  value       = google_compute_network_peering.peering.id
}

output "peering_name" {
  description = "The name of the primary peering connection"
  value       = google_compute_network_peering.peering.name
}

output "self_link" {
  description = "The network self_link associated with the peering"
  value       = google_compute_network_peering.peering.network
}

output "peering_state" {
  description = "State of the primary peering (ACTIVE, INACTIVE)"
  value       = google_compute_network_peering.peering.state
}

output "reverse_peering" {
  description = "The reverse peering connection resource (if created)"
  value       = var.create_reverse_peering ? google_compute_network_peering.reverse_peering[0] : null
}

output "peering_state_details" {
  description = "Details about the peering state"
  value       = google_compute_network_peering.peering.state_details
}
