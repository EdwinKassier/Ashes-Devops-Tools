output "all_notification_channel_ids" {
  description = "All notification channel IDs created by the alerts module."
  value       = module.alerts.all_notification_channel_ids
}

output "all_alert_policy_ids" {
  description = "Map of alert name to policy resource ID for all enabled policies."
  value       = module.alerts.all_alert_policy_ids
}
