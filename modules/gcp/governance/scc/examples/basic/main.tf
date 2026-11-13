# Example: route Security Command Center findings to Pub/Sub by severity.
# SCC findings are streamed to CMEK-encrypted topics so SIEM/alerting systems
# can consume them. (stages/organization uses the single-config form instead:
# pubsub_topic_name, config_id and filter, without notification_configs.)

locals {
  org_id     = "123456789012"
  project_id = "my-security-project"
}

module "scc_notifications" {
  source = "../../"

  org_id     = local.org_id
  project_id = local.project_id

  # Customer-managed key for the notification topics.
  kms_key_name = "projects/my-security-project/locations/europe-west2/keyRings/security/cryptoKeys/scc-notifications"

  # When notification_configs is set, the single-config inputs (config_id,
  # description, filter) are ignored. Filters use the SCC findings filter
  # syntax.
  notification_configs = {
    "high-critical" = {
      pubsub_topic_name = "scc-findings"
      description       = "HIGH and CRITICAL severity findings"
      filter            = "state=\"ACTIVE\" AND (severity=\"HIGH\" OR severity=\"CRITICAL\")"
    }
  }
}
