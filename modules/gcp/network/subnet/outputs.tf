/**
 * Copyright 2023 Ashes
 *
 * Subnet Module - Outputs
 */

output "subnet" {
  description = "The created subnet resource (every attribute except the provider-deprecated fingerprint)"
  # The google provider deprecates fingerprint; filtering it out keeps the
  # warning off every caller's plan. Read the attributes you need by name.
  value = { for k, v in google_compute_subnetwork.subnet : k => v if k != "fingerprint" }
}

output "id" {
  description = "The ID of the subnet"
  value       = google_compute_subnetwork.subnet.id
}

output "self_link" {
  description = "The URI of the subnet"
  value       = google_compute_subnetwork.subnet.self_link
}

output "name" {
  description = "The name of the subnet"
  value       = google_compute_subnetwork.subnet.name
}

output "ip_cidr_range" {
  description = "The IP CIDR range of the subnet"
  value       = google_compute_subnetwork.subnet.ip_cidr_range
}

output "gateway_address" {
  description = "The gateway address for default routing out of the subnet"
  value       = google_compute_subnetwork.subnet.gateway_address
}
