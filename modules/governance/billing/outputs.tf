output "budget_id" {
  description = "The ID of the created AWS Budget"
  value       = aws_budgets_budget.monthly.id
}

output "alert_topic_arn" {
  description = "The ARN of the SNS topic for budget alerts"
  value       = aws_sns_topic.budget_alerts.arn
} 