locals {
  # Load tile definitions from JSON template files.
  # The ternary operates on strings (not decoded tuples) so both branches have
  # the same type. jsondecode() is called after the conditional is resolved.
  cf_tiles_json = var.include_gen1_functions ? file("${path.module}/templates/cloud-functions-tiles.json") : "[]"
  cf_tiles      = jsondecode(local.cf_tiles_json)
  cr_tiles      = jsondecode(file("${path.module}/templates/cloud-run-tiles.json"))

  # Dedicated SLO scorecard tiles with configurable thresholds.
  # These sit at the top-left of the dashboard so operators see the health
  # indicators without scrolling.
  slo_tiles = [
    {
      xPos   = 0
      yPos   = 0
      width  = 12
      height = 8
      widget = {
        title = "SLO: P99 Latency"
        scorecard = {
          timeSeriesQuery = {
            timeSeriesFilter = {
              filter = "metric.type=\"run.googleapis.com/request_latencies\" resource.type=\"cloud_run_revision\""
              aggregation = {
                alignmentPeriod    = "60s"
                perSeriesAligner   = "ALIGN_PERCENTILE_99"
                crossSeriesReducer = "REDUCE_MAX"
              }
            }
            unitOverride = "ms"
          }
          thresholds = [
            {
              value     = var.latency_threshold_ms
              color     = "WARNING"
              direction = "ABOVE"
              label     = "P99 >${var.latency_threshold_ms} ms"
            }
          ]
        }
      }
    },
    {
      xPos   = 12
      yPos   = 0
      width  = 12
      height = 8
      widget = {
        title = "SLO: Error Rate"
        scorecard = {
          timeSeriesQuery = {
            timeSeriesFilter = {
              filter = "metric.type=\"run.googleapis.com/request_count\" resource.type=\"cloud_run_revision\" metric.labels.response_code_class!=\"2xx\""
              aggregation = {
                alignmentPeriod    = "60s"
                perSeriesAligner   = "ALIGN_RATE"
                crossSeriesReducer = "REDUCE_SUM"
              }
            }
          }
          thresholds = [
            {
              value     = var.error_rate_threshold_percent
              color     = "WARNING"
              direction = "ABOVE"
              label     = ">${var.error_rate_threshold_percent}% errors"
            }
          ]
        }
      }
    }
  ]

  dashboard_tiles = concat(local.slo_tiles, local.cr_tiles, local.cf_tiles)
}

resource "google_monitoring_dashboard" "compute_dashboard" {
  project = var.project_id

  dashboard_json = jsonencode({
    displayName = var.dashboard_display_name
    mosaicLayout = {
      columns = 48
      tiles   = local.dashboard_tiles
    }
  })

  lifecycle {
    # The API may return slightly different JSON than what was sent (field reordering,
    # additional metadata fields). Suppress spurious drift on every plan.
    ignore_changes = [dashboard_json]
  }
}
