output "budget_ids" {
  description = "Map of budget name to the created budget resource ID. Empty when cost governance is disabled."
  value       = { for name, b in aws_budgets_budget.this : name => b.id }
}

output "anomaly_monitor_arn" {
  description = "ARN of the Cost Anomaly Detection monitor, or null when cost governance is disabled."
  value       = try(aws_ce_anomaly_monitor.this[0].arn, null)
}
