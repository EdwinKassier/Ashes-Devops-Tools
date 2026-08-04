/**
 * Copyright 2023 Ashes
 *
 * Private Service Access Module - Outputs
 */

output "address_resource" {
  description = "The reserved global IP address resource"
  value       = google_compute_global_address.private_ip_alloc
}

output "address" {
  description = "The allocated IP address/range"
  value       = google_compute_global_address.private_ip_alloc.address
}

output "peering" {
  description = "The service networking connection resource"
  value       = google_service_networking_connection.private_service_access
}

output "id" {
  description = "The ID of the service networking connection"
  value       = google_service_networking_connection.private_service_access.id
}

output "self_link" {
  description = "The self_link of the reserved global IP address"
  value       = google_compute_global_address.private_ip_alloc.self_link
}
