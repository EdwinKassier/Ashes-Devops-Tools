output "slo_name" {
  description = "Full resource name of the SLO."
  value       = google_monitoring_slo.this.name
}

output "burn_rate_alert_policy_id" {
  description = "ID of the burn-rate alert policy, or null when not enabled."
  value       = var.enable_burn_rate_alert ? google_monitoring_alert_policy.burn_rate[0].id : null
}
