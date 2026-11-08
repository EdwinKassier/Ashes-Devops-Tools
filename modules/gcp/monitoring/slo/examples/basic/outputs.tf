output "slo_name" {
  description = "Full resource name of the SLO."
  value       = module.slo.slo_name
}

output "burn_rate_alert_policy_id" {
  description = "ID of the burn-rate alert policy."
  value       = module.slo.burn_rate_alert_policy_id
}
