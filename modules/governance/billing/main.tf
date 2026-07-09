# Google Cloud Billing Budget Module
# This module creates budget alerts using GCP Budget API

# Budget alert for monthly spending
resource "google_billing_budget" "monthly_budget" {
  billing_account = var.billing_account
  display_name    = "${var.project_name}-monthly-budget"

  budget_filter {
    projects               = length(var.projects) > 0 ? [for p in var.projects : "projects/${p}"] : null
    credit_types_treatment = "INCLUDE_ALL_CREDITS"
    labels                 = var.label_filters
    services               = var.service_filters
  }

  amount {
    specified_amount {
      currency_code = var.currency_code
      units         = tostring(var.monthly_budget_limit)
    }
  }

  # Alert at 50% of budget
  threshold_rules {
    threshold_percent = var.alert_threshold_percent
    spend_basis       = "CURRENT_SPEND"
  }

  # Alert at 90% of budget
  threshold_rules {
    threshold_percent = 0.9
    spend_basis       = "CURRENT_SPEND"
  }

  # Alert at 100% forecasted: fires before actual spend reaches budget (predictive warning)
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }

  # Alert at 100% actual: fires when real spend hits the budget limit (confirmatory alert)
  # Both 100% rules are intentional — forecasted fires earlier, actual confirms breach.
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "CURRENT_SPEND"
  }

  # Notification configuration
  all_updates_rule {
    pubsub_topic = google_pubsub_topic.budget_alerts.id

    schema_version = "1.0"

    # Optional: Add monitoring notification channels
    monitoring_notification_channels = var.notification_channels
  }
}

# Pub/Sub topic for budget alerts
resource "google_pubsub_topic" "budget_alerts" {
  name         = "${var.project_name}-budget-alerts"
  project      = var.project_id
  kms_key_name = var.kms_key_name

  labels = merge(
    {
      purpose    = "billing-alerts"
      managed-by = "terraform"
    },
    var.labels
  )
}

# Pub/Sub subscription for processing alerts
resource "google_pubsub_subscription" "budget_alerts_sub" {
  name    = "${var.project_name}-budget-alerts-sub"
  topic   = google_pubsub_topic.budget_alerts.name
  project = var.project_id

  # Push to webhook endpoint if provided
  dynamic "push_config" {
    for_each = var.webhook_endpoint != "" ? [1] : []
    content {
      push_endpoint = var.webhook_endpoint

      dynamic "oidc_token" {
        for_each = var.webhook_service_account != "" ? [1] : []
        content {
          service_account_email = var.webhook_service_account
        }
      }
    }
  }

  message_retention_duration = "86400s" # 1 day
  retain_acked_messages      = false
  ack_deadline_seconds       = 20

  labels = merge(
    {
      purpose    = "billing-alerts"
      managed-by = "terraform"
    },
    var.labels
  )
}

# Optional: Cloud Functions gen2 to send email notifications.
# Cloud Functions gen1 is deprecated and cannot satisfy the
# cloudfunctions.requireVPCConnector org policy without a VPC connector argument
# that gen1 exposes only as a direct attribute. Gen2 uses Cloud Run under the hood
# and accepts vpc_connector via service_config, making it forward-compatible.
resource "google_cloudfunctions2_function" "budget_notifier" {
  count = var.enable_email_notifications ? 1 : 0

  name     = "${var.project_name}-budget-notifier"
  project  = var.project_id
  location = var.region

  build_config {
    runtime     = "python312"
    entry_point = "notify_budget_alert"

    source {
      storage_source {
        bucket = var.functions_bucket
        object = var.function_source_object
      }
    }
  }

  service_config {
    max_instance_count = 5
    available_memory   = "256M"
    timeout_seconds    = 60

    # Satisfy cloudfunctions.requireVPCConnector org policy.
    # Pass a VPC connector resource ID when deploying in an org that enforces this policy.
    vpc_connector                 = var.vpc_connector
    vpc_connector_egress_settings = var.vpc_connector != null ? "PRIVATE_RANGES_ONLY" : null

    environment_variables = {
      RECIPIENTS   = join(",", var.email_recipients)
      PROJECT_NAME = var.project_name
    }

    # SENDGRID_API_KEY is sourced from Secret Manager at runtime — never stored as
    # a plaintext environment variable. The gen1 pattern of injecting via
    # environment_variables exposed the key in GCP console and terraform state.
    dynamic "secret_environment_variables" {
      for_each = nonsensitive(var.sendgrid_api_key_secret_id != "") ? [1] : []
      content {
        key        = "SENDGRID_API_KEY"
        project_id = var.project_id
        secret     = var.sendgrid_api_key_secret_id
        version    = "latest"
      }
    }
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.budget_alerts.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }

  labels = merge(
    {
      purpose    = "billing-notifications"
      managed-by = "terraform"
    },
    var.labels
  )
}

# IAM binding: allow the Pub/Sub service account to invoke the Cloud Run service
# backing the gen2 function (uses roles/run.invoker, not cloudfunctions.invoker).
#
# Cloud Functions gen2 deploys as a Cloud Run **v2** service. The v1 resource
# (google_cloud_run_service_iam_member) targets a different API path and will
# fail to locate the function. Use google_cloud_run_v2_service_iam_member with
# the `name` attribute (not `service`) instead.
resource "google_cloud_run_v2_service_iam_member" "budget_notifier_invoker" {
  count = var.enable_email_notifications ? 1 : 0

  project  = var.project_id
  location = var.region
  name     = google_cloudfunctions2_function.budget_notifier[0].name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${var.pubsub_service_account}"
}
