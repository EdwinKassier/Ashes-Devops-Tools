/**
 * Copyright 2024 Ashes
 *
 * Monitoring Alert Policy Module — Outputs
 */

output "email_notification_channel_ids" {
  description = "Map of email address to notification channel resource ID."
  value       = { for addr, ch in google_monitoring_notification_channel.email : addr => ch.id }
}

output "webhook_notification_channel_ids" {
  description = "Map of webhook label to notification channel resource ID."
  value       = { for label, ch in google_monitoring_notification_channel.webhook : label => ch.id }
}

output "all_notification_channel_ids" {
  description = "All notification channel IDs (created + extra). Pass this to other alert_policy module calls to share channels."
  value       = local.all_notification_channel_ids
}

output "high_cpu_alert_policy_id" {
  description = "Resource ID of the high CPU alert policy, or null when disabled."
  value       = var.enable_high_cpu_alert ? google_monitoring_alert_policy.high_cpu[0].id : null
}

output "high_memory_alert_policy_id" {
  description = "Resource ID of the high memory alert policy, or null when disabled."
  value       = var.enable_high_memory_alert ? google_monitoring_alert_policy.high_memory[0].id : null
}

output "error_rate_alert_policy_id" {
  description = "Resource ID of the error rate alert policy, or null when disabled."
  value       = var.enable_error_rate_alert ? google_monitoring_alert_policy.error_rate[0].id : null
}

output "high_latency_alert_policy_id" {
  description = "Resource ID of the high latency alert policy, or null when disabled."
  value       = var.enable_high_latency_alert ? google_monitoring_alert_policy.high_latency[0].id : null
}

output "uptime_alert_policy_id" {
  description = "Resource ID of the uptime alert policy, or null when disabled."
  value       = var.enable_uptime_alert && length(var.uptime_check_ids) > 0 ? google_monitoring_alert_policy.uptime[0].id : null
}

output "log_based_alert_policy_id" {
  description = "Resource ID of the log-based alert policy, or null when disabled."
  value       = var.enable_log_based_alert && var.log_filter != null ? google_monitoring_alert_policy.log_based[0].id : null
}

output "all_alert_policy_ids" {
  description = "Map of alert name to policy resource ID for all enabled policies."
  value = merge(
    var.enable_high_cpu_alert ? { "high_cpu" = google_monitoring_alert_policy.high_cpu[0].id } : {},
    var.enable_high_memory_alert ? { "high_memory" = google_monitoring_alert_policy.high_memory[0].id } : {},
    var.enable_error_rate_alert ? { "error_rate" = google_monitoring_alert_policy.error_rate[0].id } : {},
    var.enable_high_latency_alert ? { "high_latency" = google_monitoring_alert_policy.high_latency[0].id } : {},
    (var.enable_uptime_alert && length(var.uptime_check_ids) > 0) ? { "uptime" = google_monitoring_alert_policy.uptime[0].id } : {},
    (var.enable_log_based_alert && var.log_filter != null) ? { "log_based" = google_monitoring_alert_policy.log_based[0].id } : {},
  )
}
