/**
 * Copyright 2023 Ashes
 *
 * VPC Flow Logs Export Module - Outputs
 */

# Standard interface outputs
output "id" {
  description = "The ID of the log sink"
  value       = google_logging_project_sink.flow_logs_sink.id
}

output "self_link" {
  description = "The ID of the log sink (log sinks use id as identifier)"
  value       = google_logging_project_sink.flow_logs_sink.id
}

output "name" {
  description = "The name of the log sink"
  value       = google_logging_project_sink.flow_logs_sink.name
}

# Sink-specific outputs
output "sink" {
  description = "The log sink resource"
  value       = google_logging_project_sink.flow_logs_sink
}

output "writer_identity" {
  description = "The service account identity for the sink writer"
  value       = google_logging_project_sink.flow_logs_sink.writer_identity
}

output "destination" {
  description = "The destination of the log sink"
  value       = google_logging_project_sink.flow_logs_sink.destination
}

# BigQuery outputs
output "bigquery_dataset" {
  description = "The BigQuery dataset resource (if created)"
  value       = var.create_bigquery_dataset ? google_bigquery_dataset.flow_logs[0] : null
}

output "bigquery_dataset_id" {
  description = "The BigQuery dataset ID (if created)"
  value       = var.create_bigquery_dataset ? google_bigquery_dataset.flow_logs[0].dataset_id : null
}

# Storage outputs
output "storage_bucket" {
  description = "The Cloud Storage bucket resource (if created)"
  value       = var.create_storage_bucket ? google_storage_bucket.flow_logs[0] : null
}

output "storage_bucket_name" {
  description = "The Cloud Storage bucket name (if created)"
  value       = var.create_storage_bucket ? google_storage_bucket.flow_logs[0].name : null
}
