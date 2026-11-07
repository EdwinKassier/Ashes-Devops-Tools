# =============================================================================
# SCC API VERSION (v1 -> v2 migration)
#   v1   - only the v1 resources (default; existing estates unchanged)
#   both - v1 resources plus their v2 twins (create v2, verify)
#   v2   - only the v2 resources (flip: the v1 configs are destroyed)
# Pub/Sub topics are shared across versions, so their addresses never change.
# v1 and v2 cannot see each other's configs: see docs/runbooks/scc-v2-migration.md.
# =============================================================================

locals {
  v1_enabled = contains(["v1", "both"], var.scc_api_version)
  v2_enabled = contains(["v2", "both"], var.scc_api_version)

  # One entry per notification config, whichever mode (legacy single / multi) is active.
  v2_notification_configs = local.v2_enabled ? (
    length(var.notification_configs) == 0 ? {
      (var.config_id) = {
        topic_id    = google_pubsub_topic.scc_notifications[0].id
        topic_name  = google_pubsub_topic.scc_notifications[0].name
        description = var.description
        filter      = var.filter
      }
      } : {
      for k, v in var.notification_configs : k => {
        topic_id    = google_pubsub_topic.scc_notifications_multi[k].id
        topic_name  = google_pubsub_topic.scc_notifications_multi[k].name
        description = v.description
        filter      = v.filter
      }
    }
  ) : {}
}

# =============================================================================
# LEGACY SINGLE CONFIG (Backward Compatibility)
# =============================================================================

resource "google_pubsub_topic" "scc_notifications" {
  count        = length(var.notification_configs) == 0 ? 1 : 0
  name         = var.pubsub_topic_name
  project      = var.project_id
  kms_key_name = var.kms_key_name
  labels       = var.labels
}

resource "google_scc_notification_config" "notification_config" {
  count        = length(var.notification_configs) == 0 && local.v1_enabled ? 1 : 0
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
  count   = length(var.notification_configs) == 0 && local.v1_enabled ? 1 : 0
  topic   = google_pubsub_topic.scc_notifications[0].name
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_scc_notification_config.notification_config[0].service_account}"
}

# =============================================================================
# ADVANCED: MULTIPLE NOTIFICATION CONFIGS (Severity-Based Routing)
# =============================================================================

# Create Pub/Sub topics for each notification config
resource "google_pubsub_topic" "scc_notifications_multi" {
  for_each = var.notification_configs

  name         = each.value.pubsub_topic_name
  project      = var.project_id
  kms_key_name = var.kms_key_name

  labels = merge(var.labels, {
    scc-config = each.key
    managed-by = "terraform"
  })
}

# Create notification configs for severity-based routing
resource "google_scc_notification_config" "notification_config_multi" {
  for_each = local.v1_enabled ? var.notification_configs : {}

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
  for_each = local.v1_enabled ? var.notification_configs : {}

  topic   = google_pubsub_topic.scc_notifications_multi[each.key].name
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_scc_notification_config.notification_config_multi[each.key].service_account}"
}

# =============================================================================
# SCC v2 (scc_api_version = "v2" or "both")
# =============================================================================

resource "google_scc_v2_organization_notification_config" "this" {
  for_each = local.v2_notification_configs

  config_id    = each.key
  organization = var.org_id
  location     = var.scc_location
  description  = each.value.description
  pubsub_topic = each.value.topic_id

  streaming_config {
    filter = each.value.filter
  }
}

# The v2 notification service account differs from the v1 one.
resource "google_pubsub_topic_iam_member" "scc_publisher_v2" {
  for_each = local.v2_notification_configs

  topic   = each.value.topic_name
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_scc_v2_organization_notification_config.this[each.key].service_account}"
}

# =============================================================================
# MUTE CONFIGS (follow scc_api_version; v1 and v2 mute configs are separate)
# =============================================================================

resource "google_scc_mute_config" "this" {
  for_each = local.v1_enabled ? var.mute_configs : {}

  mute_config_id = each.key
  parent         = "organizations/${var.org_id}"
  description    = each.value.description
  filter         = each.value.filter
  type           = each.value.type
}

resource "google_scc_v2_organization_mute_config" "this" {
  for_each = local.v2_enabled ? var.mute_configs : {}

  mute_config_id = each.key
  organization   = var.org_id
  location       = var.scc_location
  description    = each.value.description
  filter         = each.value.filter
  type           = each.value.type
}
