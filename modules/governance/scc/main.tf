resource "google_pubsub_topic" "scc_notifications" {
  name    = var.pubsub_topic_name
  project = var.project_id
}

resource "google_scc_notification_config" "notification_config" {
  config_id    = var.config_id
  organization = var.org_id
  description  = var.description
  pubsub_topic = google_pubsub_topic.scc_notifications.id

  streaming_config {
    filter = var.filter
  }
}

# Grant SCC service account permissions to publish to the topic
resource "google_pubsub_topic_iam_member" "scc_publisher" {
  topic  = google_pubsub_topic.scc_notifications.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_scc_notification_config.notification_config.service_account}"
}
