output "watch_alert_policy_ids" {
  description = "Map of watch name to the created alert policy ID."
  value       = { for k, p in google_monitoring_alert_policy.watch : k => p.id }
}

output "log_export_error_alert_policy_id" {
  description = "ID of the audit-sink export-error alert policy, or null when disabled."
  value       = var.enable && var.enable_log_export_error_alert ? google_monitoring_alert_policy.log_export_error[0].id : null
}

output "notification_channel_ids" {
  description = "IDs of the notification channels this module created (email and webhook)."
  value = concat(
    [for ch in google_monitoring_notification_channel.email : ch.id],
    [for ch in google_monitoring_notification_channel.webhook : ch.id],
  )
}

output "watched_names" {
  description = "Names of the guardrail watches that are active."
  value       = keys(var.enable ? var.watches : {})
}
