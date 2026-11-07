/**
 * Copyright 2026 Ashes
 *
 * Cloud Run Job (v2) Module - Outputs
 */

output "name" {
  description = "The name of the Cloud Run job."
  value       = google_cloud_run_v2_job.this.name
}

output "id" {
  description = "The fully qualified identifier of the Cloud Run job."
  value       = google_cloud_run_v2_job.this.id
}

output "service_account_email" {
  description = "The service account the job's tasks run as."
  value       = var.service_account_email
}
