# Google Cloud Billing Budget Module
# This module creates budget alerts using GCP Budget API

# Budget alert for monthly spending
resource "google_billing_budget" "monthly_budget" {
  billing_account = var.billing_account
  display_name    = "${var.project_name}-monthly-budget"

  budget_filter {
    projects               = length(var.projects) > 0 ? var.projects : null
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

  # Alert at 100% of budget (forecasted)
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }

  # Alert at 100% of budget (actual)
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
  name    = "${var.project_name}-budget-alerts"
  project = var.project_id

  labels = merge(
    {
      purpose    = "billing-alerts"
      managed-by = "terraform"
    },
    var.tags
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
    var.tags
  )
}

# Optional: Cloud Function to send email notifications
resource "google_cloudfunctions_function" "budget_notifier" {
  count = var.enable_email_notifications ? 1 : 0

  name        = "${var.project_name}-budget-notifier"
  project     = var.project_id
  region      = var.region
  runtime     = "python310"
  entry_point = "notify_budget_alert"

  available_memory_mb   = 256
  source_archive_bucket = var.functions_bucket
  source_archive_object = var.function_source_object
  timeout               = 60

  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.budget_alerts.id
  }

  environment_variables = {
    SENDGRID_API_KEY = var.sendgrid_api_key_secret_id
    RECIPIENTS       = join(",", var.email_recipients)
    PROJECT_NAME     = var.project_name
  }

  labels = merge(
    {
      purpose    = "billing-notifications"
      managed-by = "terraform"
    },
    var.tags
  )
}

# IAM binding for Pub/Sub to invoke Cloud Function
resource "google_cloudfunctions_function_iam_member" "invoker" {
  count = var.enable_email_notifications ? 1 : 0

  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.budget_notifier[0].name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${var.pubsub_service_account}"
}
