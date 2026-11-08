output "watched_names" {
  description = "Names of the active guardrail watches."
  value       = module.control_plane_alerts.watched_names
}

output "org_log_route_sink_name" {
  description = "Aggregated org sink that routes audit logs into the project."
  value       = module.control_plane_alerts.org_log_route_sink_name
}

output "cis_log_metric_names" {
  description = "CIS log-metric key to log-based metric name."
  value       = module.control_plane_alerts.cis_log_metric_names
}
