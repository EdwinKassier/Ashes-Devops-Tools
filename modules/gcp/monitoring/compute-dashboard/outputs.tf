# -----------------------------------------------------------------------------
# Dashboard Outputs
# -----------------------------------------------------------------------------

output "dashboard_id" {
  description = "The ID of the created monitoring dashboard"
  value       = google_monitoring_dashboard.compute_dashboard.id
}

output "dashboard_console_url" {
  description = "Direct URL to access the dashboard in the GCP Console"
  # The `id` attribute is the full resource name (projects/N/dashboards/X); the
  # console builder URL expects only the bare dashboard id, so strip the prefix.
  value = "https://console.cloud.google.com/monitoring/dashboards/builder/${element(split("/", google_monitoring_dashboard.compute_dashboard.id), length(split("/", google_monitoring_dashboard.compute_dashboard.id)) - 1)}?project=${var.project_id}"
}
