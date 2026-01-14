# =============================================================================
# LEGACY SINGLE CONFIG OUTPUTS
# =============================================================================

output "topic_id" {
  description = "The ID of the created Pub/Sub topic (legacy single config)"
  value       = length(var.notification_configs) == 0 ? google_pubsub_topic.scc_notifications[0].id : null
}

output "topic_name" {
  description = "The name of the created Pub/Sub topic (legacy single config)"
  value       = length(var.notification_configs) == 0 ? google_pubsub_topic.scc_notifications[0].name : null
}

output "notification_config_name" {
  description = "The resource name of the notification config (legacy single config)"
  value       = length(var.notification_configs) == 0 ? google_scc_notification_config.notification_config[0].name : null
}

# =============================================================================
# MULTIPLE NOTIFICATION CONFIGS OUTPUTS
# =============================================================================

output "topics" {
  description = "Map of Pub/Sub topics created for severity-based routing"
  value = {
    for k, topic in google_pubsub_topic.scc_notifications_multi : k => {
      id   = topic.id
      name = topic.name
    }
  }
}

output "notification_configs" {
  description = "Map of SCC notification configurations for severity-based routing"
  value = {
    for k, config in google_scc_notification_config.notification_config_multi : k => {
      name            = config.name
      service_account = config.service_account
    }
  }
}
