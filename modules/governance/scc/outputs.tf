output "topic_id" {
  description = "The ID of the created Pub/Sub topic"
  value       = google_pubsub_topic.scc_notifications.id
}

output "topic_name" {
  description = "The name of the created Pub/Sub topic"
  value       = google_pubsub_topic.scc_notifications.name
}

output "notification_config_name" {
  description = "The resource name of the notification config"
  value       = google_scc_notification_config.notification_config.name
}
