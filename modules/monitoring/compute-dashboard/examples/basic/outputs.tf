output "dashboard_url" {
  description = "GCP Console URL to open the created dashboard"
  value       = module.compute_dashboard.dashboard_console_url
}
