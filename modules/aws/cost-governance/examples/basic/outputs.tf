output "budget_ids" {
  description = "Map of budget name to budget resource ID."
  value       = module.cost_governance.budget_ids
}

output "anomaly_monitor_arn" {
  description = "ARN of the Cost Anomaly Detection monitor."
  value       = module.cost_governance.anomaly_monitor_arn
}
