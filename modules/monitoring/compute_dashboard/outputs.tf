# -----------------------------------------------------------------------------
# Dashboard Outputs
# -----------------------------------------------------------------------------

output "dashboard_id" {
  description = "The ID of the created monitoring dashboard"
  value       = google_monitoring_dashboard.compute_dashboard.id
}

output "dashboard_console_url" {
  description = "Direct URL to access the dashboard in the GCP Console"
  value       = "https://console.cloud.google.com/monitoring/dashboards/builder/${google_monitoring_dashboard.compute_dashboard.id}?project=${var.project_id}"
}
