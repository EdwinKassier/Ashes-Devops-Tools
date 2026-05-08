/**
 * Copyright 2024 Ashes
 *
 * Monitoring Alert Policy Module
 *
 * Creates Cloud Monitoring alert policies and notification channels.
 * Supports email, Slack/webhook notifications, and common GCP metric alerts
 * (CPU, memory, error rate, latency, uptime, and log-based).
 *
 * Usage:
 *   module "alerts" {
 *     source     = "../../modules/monitoring/alert_policy"
 *     project_id = "my-project"
 *     notification_email_addresses = ["ops@example.com"]
 *     notification_webhook_urls = {
 *       "slack-ops" = "https://hooks.slack.com/services/..."
 *     }
 *   }
 */

locals {
  prefix = var.alert_display_name_prefix != "" ? "${var.alert_display_name_prefix}: " : ""

  # Collect all notification channel IDs (created + pre-existing).
  all_notification_channel_ids = concat(
    [for ch in google_monitoring_notification_channel.email : ch.id],
    [for ch in google_monitoring_notification_channel.webhook : ch.id],
    var.extra_notification_channel_ids,
  )

  duration_str = "${var.alert_duration}s"
}

# ── Notification Channels ──────────────────────────────────────────────────────

resource "google_monitoring_notification_channel" "email" {
  for_each = toset(var.notification_email_addresses)

  project      = var.project_id
  display_name = "Email: ${each.value}"
  type         = "email"

  labels = {
    email_address = each.value
  }

  user_labels = var.labels
}

resource "google_monitoring_notification_channel" "webhook" {
  for_each = var.notification_webhook_urls

  project      = var.project_id
  display_name = "Webhook: ${each.key}"
  type         = "webhook_tokenauth"

  labels = {
    url = each.value
  }

  user_labels = var.labels
}

# ── CPU Utilisation Alert ──────────────────────────────────────────────────────

resource "google_monitoring_alert_policy" "high_cpu" {
  count = var.enable_high_cpu_alert ? 1 : 0

  project      = var.project_id
  display_name = "${local.prefix}High CPU Utilisation"
  combiner     = "OR"

  conditions {
    display_name = "CPU utilisation > ${var.cpu_utilization_threshold * 100}%"

    condition_threshold {
      filter          = "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" resource.type=\"gce_instance\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.cpu_utilization_threshold
      duration        = local.duration_str

      aggregations {
        alignment_period   = "${var.alert_alignment_period}s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = local.all_notification_channel_ids

  alert_strategy {
    auto_close = "604800s" # 7 days
  }

  documentation {
    content   = "CPU utilisation exceeded ${var.cpu_utilization_threshold * 100}% for ${var.alert_duration}s. Investigate with: `gcloud compute instances describe <instance>`"
    mime_type = "text/markdown"
  }
}

# ── Memory Utilisation Alert ───────────────────────────────────────────────────

resource "google_monitoring_alert_policy" "high_memory" {
  count = var.enable_high_memory_alert ? 1 : 0

  project      = var.project_id
  display_name = "${local.prefix}High Memory Utilisation"
  combiner     = "OR"

  conditions {
    display_name = "Memory utilisation > ${var.memory_utilization_threshold * 100}%"

    condition_threshold {
      # agent.googleapis.com metrics require the Cloud Monitoring agent or Ops Agent.
      filter          = "metric.type=\"agent.googleapis.com/memory/percent_used\" resource.type=\"gce_instance\" metric.labels.state=\"used\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.memory_utilization_threshold * 100 # agent metric is 0–100
      duration        = local.duration_str

      aggregations {
        alignment_period   = "${var.alert_alignment_period}s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = local.all_notification_channel_ids

  alert_strategy {
    auto_close = "604800s"
  }

  documentation {
    content   = "Memory utilisation exceeded ${var.memory_utilization_threshold * 100}% for ${var.alert_duration}s."
    mime_type = "text/markdown"
  }
}

# ── Cloud Run Error Rate Alert ─────────────────────────────────────────────────

resource "google_monitoring_alert_policy" "error_rate" {
  count = var.enable_error_rate_alert ? 1 : 0

  project      = var.project_id
  display_name = "${local.prefix}High 5xx Error Rate (Cloud Run)"
  combiner     = "OR"

  conditions {
    display_name = "5xx error rate > ${var.error_rate_threshold_percent} req/s"

    condition_threshold {
      filter = join(" AND ", [
        "metric.type=\"run.googleapis.com/request_count\"",
        "resource.type=\"cloud_run_revision\"",
        "metric.labels.response_code_class=\"5xx\"",
      ])
      comparison      = "COMPARISON_GT"
      threshold_value = var.error_rate_threshold_percent
      duration        = local.duration_str

      aggregations {
        alignment_period     = "${var.alert_alignment_period}s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  notification_channels = local.all_notification_channel_ids

  alert_strategy {
    auto_close = "86400s" # 1 day
  }

  documentation {
    content   = "Cloud Run 5xx error rate exceeded ${var.error_rate_threshold_percent} req/s. Check service logs: `gcloud run services logs read`"
    mime_type = "text/markdown"
  }
}

# ── Cloud Run P99 Latency Alert ────────────────────────────────────────────────

resource "google_monitoring_alert_policy" "high_latency" {
  count = var.enable_high_latency_alert ? 1 : 0

  project      = var.project_id
  display_name = "${local.prefix}High P99 Latency (Cloud Run)"
  combiner     = "OR"

  conditions {
    display_name = "P99 latency > ${var.latency_p99_threshold_ms}ms"

    condition_threshold {
      filter = join(" AND ", [
        "metric.type=\"run.googleapis.com/request_latencies\"",
        "resource.type=\"cloud_run_revision\"",
      ])
      comparison      = "COMPARISON_GT"
      threshold_value = var.latency_p99_threshold_ms
      duration        = local.duration_str

      aggregations {
        alignment_period     = "${var.alert_alignment_period}s"
        per_series_aligner   = "ALIGN_PERCENTILE_99"
        cross_series_reducer = "REDUCE_MAX"
      }
    }
  }

  notification_channels = local.all_notification_channel_ids

  alert_strategy {
    auto_close = "86400s"
  }

  documentation {
    content   = "Cloud Run P99 latency exceeded ${var.latency_p99_threshold_ms}ms for ${var.alert_duration}s. Profile the service or check for downstream dependencies."
    mime_type = "text/markdown"
  }
}

# ── Uptime Check Failure Alert ─────────────────────────────────────────────────

resource "google_monitoring_alert_policy" "uptime" {
  count = var.enable_uptime_alert && length(var.uptime_check_ids) > 0 ? 1 : 0

  project      = var.project_id
  display_name = "${local.prefix}Uptime Check Failure"
  combiner     = "OR"

  dynamic "conditions" {
    for_each = var.uptime_check_ids
    content {
      display_name = "Uptime check failed: ${conditions.value}"

      condition_threshold {
        filter = join(" AND ", [
          "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\"",
          "resource.type=\"uptime_url\"",
          "metric.labels.check_id=\"${conditions.value}\"",
        ])
        comparison      = "COMPARISON_LT"
        threshold_value = 1
        duration        = local.duration_str

        aggregations {
          alignment_period     = "${var.alert_alignment_period}s"
          per_series_aligner   = "ALIGN_NEXT_OLDER"
          cross_series_reducer = "REDUCE_COUNT_FALSE"
          group_by_fields      = ["resource.label.host"]
        }
      }
    }
  }

  notification_channels = local.all_notification_channel_ids

  alert_strategy {
    auto_close = "3600s" # 1 hour
  }

  documentation {
    content   = "Uptime check failed. Verify the endpoint is reachable and the health check path returns 2xx."
    mime_type = "text/markdown"
  }
}

# ── Log-Based Alert ────────────────────────────────────────────────────────────

resource "google_monitoring_alert_policy" "log_based" {
  count = var.enable_log_based_alert && var.log_filter != null ? 1 : 0

  project      = var.project_id
  display_name = "${local.prefix}${var.log_alert_display_name}"
  combiner     = "OR"

  conditions {
    display_name = var.log_alert_display_name

    condition_matched_log {
      filter = var.log_filter
    }
  }

  notification_channels = local.all_notification_channel_ids

  alert_strategy {
    # Log-based alerts auto-close after 30 minutes if no further matches.
    auto_close = "1800s"
    notification_rate_limit {
      period = "300s" # At most one notification per 5 minutes for this log pattern.
    }
  }

  documentation {
    content   = "Log-based alert triggered. Filter: `${var.log_filter}`"
    mime_type = "text/markdown"
  }
}
