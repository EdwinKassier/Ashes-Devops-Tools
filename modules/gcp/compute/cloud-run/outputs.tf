/**
 * Copyright 2023 Ashes
 *
 * Cloud Run (v2) Module - Outputs
 */

output "name" {
  description = "The name of the Cloud Run service."
  value       = google_cloud_run_v2_service.this.name
}

output "uri" {
  description = "The main URI at which the Cloud Run service is reachable."
  value       = google_cloud_run_v2_service.this.uri
}

output "latest_ready_revision" {
  description = "The name of the latest revision that is serving ready traffic."
  value       = google_cloud_run_v2_service.this.latest_ready_revision
}

output "id" {
  description = "The fully qualified identifier of the Cloud Run service."
  value       = google_cloud_run_v2_service.this.id
}

output "ingress" {
  description = "The ingress traffic policy applied to the service."
  value       = google_cloud_run_v2_service.this.ingress
}
