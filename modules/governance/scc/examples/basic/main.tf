# Example: configure Security Command Center notification routing to Pub/Sub.
# SCC findings are streamed to a topic so SIEM/alerting systems can consume them.

locals {
  org_id     = "123456789012"
  project_id = "my-security-project"
}

module "scc_notifications" {
  source = "../../"

  org_id     = local.org_id
  project_id = local.project_id
  config_id  = "high-severity-findings"

  description = "Stream HIGH and CRITICAL findings to Pub/Sub"

  # Filter expression uses SCC's CEL syntax.
  filter = "severity = \"HIGH\" OR severity = \"CRITICAL\""

  notification_configs = {
    "high-critical" = {
      pubsub_topic_name = "scc-findings"
      description       = "HIGH and CRITICAL severity findings"
      filter            = "state=\"ACTIVE\" AND (severity=\"HIGH\" OR severity=\"CRITICAL\")"
    }
  }
}
