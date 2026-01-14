# =============================================================================
# LEGACY SINGLE CONFIG (Backward Compatibility)
# =============================================================================

resource "google_pubsub_topic" "scc_notifications" {
  count   = length(var.notification_configs) == 0 ? 1 : 0
  name    = var.pubsub_topic_name
  project = var.project_id
}

resource "google_scc_notification_config" "notification_config" {
  count        = length(var.notification_configs) == 0 ? 1 : 0
  config_id    = var.config_id
  organization = var.org_id
  description  = var.description
  pubsub_topic = google_pubsub_topic.scc_notifications[0].id

  streaming_config {
    filter = var.filter
  }
}

# Grant SCC service account permissions to publish to the topic (legacy)
resource "google_pubsub_topic_iam_member" "scc_publisher" {
  count  = length(var.notification_configs) == 0 ? 1 : 0
  topic  = google_pubsub_topic.scc_notifications[0].name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_scc_notification_config.notification_config[0].service_account}"
}

# =============================================================================
# ADVANCED: MULTIPLE NOTIFICATION CONFIGS (Severity-Based Routing)
# =============================================================================

# Create Pub/Sub topics for each notification config
resource "google_pubsub_topic" "scc_notifications_multi" {
  for_each = var.notification_configs

  name    = each.value.pubsub_topic_name
  project = var.project_id

  labels = {
    scc-config = each.key
    managed-by = "terraform"
  }
}

# Create notification configs for severity-based routing
resource "google_scc_notification_config" "notification_config_multi" {
  for_each = var.notification_configs

  config_id    = each.key
  organization = var.org_id
  description  = each.value.description
  pubsub_topic = google_pubsub_topic.scc_notifications_multi[each.key].id

  streaming_config {
    filter = each.value.filter
  }
}

# Grant SCC service account permissions to publish to each topic
resource "google_pubsub_topic_iam_member" "scc_publisher_multi" {
  for_each = var.notification_configs

  topic   = google_pubsub_topic.scc_notifications_multi[each.key].name
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_scc_notification_config.notification_config_multi[each.key].service_account}"
}
