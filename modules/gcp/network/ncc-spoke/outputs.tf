/**
 * Copyright 2023 Ashes
 *
 * NCC Spoke Module - Outputs
 */

output "id" {
  description = "The spoke ID."
  value       = google_network_connectivity_spoke.this.id
}

output "name" {
  description = "The spoke name."
  value       = google_network_connectivity_spoke.this.name
}

output "group" {
  description = "The hub group ID the spoke (and its producer spokes) joined."
  value       = google_network_connectivity_spoke.this.group
}

output "state" {
  description = "The spoke state (ACTIVE once accepted; a spoke in another project than the hub stays PENDING until the hub admin accepts it)."
  value       = google_network_connectivity_spoke.this.state
}

output "producer_spoke_ids" {
  description = "Producer VPC spoke IDs, keyed by producer_vpc_networks key."
  value       = { for k, v in google_network_connectivity_spoke.producer : k => v.id }
}
