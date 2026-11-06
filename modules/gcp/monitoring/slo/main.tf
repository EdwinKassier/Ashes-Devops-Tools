# Service-level objective for a monitored service (the platform had no
# app observability). Attaches an availability or latency SLO to an existing
# monitored service (e.g. the one GCP auto-creates for a Cloud Run service), and
# optionally alerts when the error budget burns too fast.

resource "google_monitoring_slo" "this" {
  project      = var.project_id
  service      = var.service_id
  slo_id       = var.slo_id
  display_name = var.display_name

  goal                = var.goal
  rolling_period_days = var.rolling_period_days

  basic_sli {
    dynamic "availability" {
      for_each = var.sli_type == "availability" ? [1] : []
      content {
        enabled = true
      }
    }

    dynamic "latency" {
      for_each = var.sli_type == "latency" ? [1] : []
      content {
        threshold = var.latency_threshold
      }
    }
  }
}

# Alert on fast error-budget burn (opt-in). A high burn rate means the SLO will be
# missed well before the rolling window ends.
resource "google_monitoring_alert_policy" "burn_rate" {
  count = var.enable_burn_rate_alert ? 1 : 0

  project      = var.project_id
  display_name = "${var.display_name} - error budget burn"
  combiner     = "OR"

  conditions {
    display_name = "Error budget burn rate > ${var.burn_rate_threshold}"
    condition_threshold {
      filter          = "select_slo_burn_rate(\"${google_monitoring_slo.this.name}\", \"${var.burn_rate_lookback}\")"
      comparison      = "COMPARISON_GT"
      threshold_value = var.burn_rate_threshold
      duration        = "0s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = var.notification_channels

  documentation {
    content = "The error budget for ${var.display_name} is burning faster than ${var.burn_rate_threshold}x. At this rate the ${var.rolling_period_days}-day SLO will be missed. Investigate the service."
  }
}
