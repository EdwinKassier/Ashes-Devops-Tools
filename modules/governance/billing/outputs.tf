output "budget_id" {
  description = "The ID of the budget"
  value       = google_billing_budget.monthly_budget.name
}

output "budget_name" {
  description = "The display name of the budget"
  value       = google_billing_budget.monthly_budget.display_name
}

output "pubsub_topic_id" {
  description = "The ID of the Pub/Sub topic for budget alerts"
  value       = google_pubsub_topic.budget_alerts.id
}

output "pubsub_topic_name" {
  description = "The name of the Pub/Sub topic for budget alerts"
  value       = google_pubsub_topic.budget_alerts.name
}

output "pubsub_subscription_id" {
  description = "The ID of the Pub/Sub subscription for budget alerts"
  value       = google_pubsub_subscription.budget_alerts_sub.id
}

output "pubsub_subscription_name" {
  description = "The name of the Pub/Sub subscription for budget alerts"
  value       = google_pubsub_subscription.budget_alerts_sub.name
}

output "budget_notifier_function_name" {
  description = "The name of the Cloud Function for budget notifications"
  value       = var.enable_email_notifications ? google_cloudfunctions_function.budget_notifier[0].name : null
}

output "budget_notifier_function_url" {
  description = "The URL of the Cloud Function for budget notifications"
  value       = var.enable_email_notifications ? google_cloudfunctions_function.budget_notifier[0].https_trigger_url : null
}

output "budget_amount" {
  description = "The configured budget amount"
  value = {
    currency = var.currency_code
    amount   = var.monthly_budget_limit
  }
}

output "alert_thresholds" {
  description = "The configured alert thresholds"
  value = [
    "${var.alert_threshold_percent * 100}% (Current Spend)",
    "90% (Current Spend)",
    "100% (Forecasted Spend)",
    "100% (Current Spend)"
  ]
}
