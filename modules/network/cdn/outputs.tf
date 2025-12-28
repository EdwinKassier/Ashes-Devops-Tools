/**
 * Copyright 2023 Ashes
 *
 * CDN Module - Outputs
 */

output "id" {
  description = "The ID of the CDN load balancer IP address"
  value       = google_compute_global_address.default.id
}

output "self_link" {
  description = "The self link of the backend service"
  value       = google_compute_backend_service.default.self_link
}

output "load_balancer_ip" {
  description = "The global IP address of the load balancer"
  value       = google_compute_global_address.default.address
}

output "backend_service_id" {
  description = "The ID of the backend service"
  value       = google_compute_backend_service.default.id
}

output "backend_service_self_link" {
  description = "The self link of the backend service"
  value       = google_compute_backend_service.default.self_link
}

output "url_map_id" {
  description = "The ID of the URL map"
  value       = google_compute_url_map.default.id
}

output "https_proxy_id" {
  description = "The ID of the HTTPS proxy"
  value       = google_compute_target_https_proxy.default.id
}
