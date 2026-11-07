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
  value       = length(google_scc_notification_config.notification_config) > 0 ? google_scc_notification_config.notification_config[0].name : null
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

output "v2_notification_configs" {
  description = "Map of SCC v2 notification configs (empty unless scc_api_version is both or v2)"
  value = {
    for k, config in google_scc_v2_organization_notification_config.this : k => {
      name            = config.name
      service_account = config.service_account
    }
  }
}

output "mute_config_names" {
  description = "Resource names of the mute configs (v1 and/or v2 per scc_api_version)"
  value = merge(
    { for k, m in google_scc_mute_config.this : "v1/${k}" => m.name },
    { for k, m in google_scc_v2_organization_mute_config.this : "v2/${k}" => m.name },
  )
}
