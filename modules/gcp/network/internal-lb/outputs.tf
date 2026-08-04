/**
 * Copyright 2023 Ashes
 *
 * Internal HTTP(S) Load Balancer Module - Outputs
 */

# Standard interface outputs
output "id" {
  description = "The ID of the forwarding rule"
  value       = google_compute_forwarding_rule.forwarding_rule.id
}

output "self_link" {
  description = "The self_link of the forwarding rule"
  value       = google_compute_forwarding_rule.forwarding_rule.self_link
}

output "name" {
  description = "The name of the forwarding rule"
  value       = google_compute_forwarding_rule.forwarding_rule.name
}

output "forwarding_rule" {
  description = "The full forwarding rule resource"
  value       = google_compute_forwarding_rule.forwarding_rule
}

output "ip_address" {
  description = "The internal IP address of the load balancer"
  value       = google_compute_forwarding_rule.forwarding_rule.ip_address
}

output "backend_service" {
  description = "The backend service resource"
  value       = google_compute_region_backend_service.backend
}

output "backend_service_id" {
  description = "The ID of the backend service"
  value       = google_compute_region_backend_service.backend.id
}

output "backend_service_self_link" {
  description = "The self_link of the backend service"
  value       = google_compute_region_backend_service.backend.self_link
}

output "health_check" {
  description = "The health check resource (if created)"
  value       = var.create_health_check ? google_compute_health_check.health_check[0] : null
}

output "url_map" {
  description = "The URL map resource (if L7)"
  value       = var.is_l7 ? google_compute_region_url_map.url_map[0] : null
}

output "static_ip_address" {
  description = "The static IP address resource (if created)"
  value       = var.create_static_ip ? google_compute_address.internal_ip[0] : null
}
