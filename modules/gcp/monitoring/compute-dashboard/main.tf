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
      width  = 24
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
      xPos   = 24
      yPos   = 0
      width  = 24
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

  # Normalise the JSON to the form the Monitoring API returns, so the plan shows
  # no diff when nothing changed. The google provider already suppresses fields
  # the API adds (etag, name, ...), but fields we send that the API drops still
  # show as a diff. proto3 JSON drops zero values, so a tile at xPos/yPos 0
  # comes back without that key. jsonencode sorts object keys (height, widget,
  # width, xPos, yPos), so a zero position always follows a comma and precedes
  # a comma or the closing brace. Two passes, because the first match of
  # `,"xPos":0,"yPos":0}` consumes the comma the yPos match needs.
  dashboard_json_raw = jsonencode({
    displayName = var.dashboard_display_name
    mosaicLayout = {
      columns = 48
      tiles   = local.dashboard_tiles
    }
  })
  dashboard_json = replace(
    replace(local.dashboard_json_raw, "/,\"(?:xPos|yPos)\":0([,}])/", "$1"),
    "/,\"(?:xPos|yPos)\":0([,}])/", "$1",
  )
}

resource "google_monitoring_dashboard" "compute_dashboard" {
  project = var.project_id

  # No ignore_changes: dashboard_json is the dashboard's entire content, so a
  # tile or threshold change must reach the API. local.dashboard_json is
  # normalised to the API's returned form to avoid perpetual diffs.
  dashboard_json = local.dashboard_json
}
