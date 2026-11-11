# Plan assertions for the compute dashboard: the dashboard content must follow
# the module inputs on every plan (no ignore_changes on dashboard_json), and the
# JSON must be normalised to the form the Monitoring API returns.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id = "mock-project"
}

run "default_dashboard" {
  command = plan

  assert {
    condition     = google_monitoring_dashboard.compute_dashboard.dashboard_json == local.dashboard_json
    error_message = "the planned dashboard_json must be the module's normalised JSON."
  }

  assert {
    condition     = jsondecode(google_monitoring_dashboard.compute_dashboard.dashboard_json).mosaicLayout.tiles[0].widget.scorecard.thresholds[0].value == 1000
    error_message = "the default P99 latency threshold tile must be planned at 1000 ms."
  }

  # proto3 JSON drops zero values, so a zero tile position must not be sent.
  assert {
    condition     = !strcontains(google_monitoring_dashboard.compute_dashboard.dashboard_json, "\"xPos\":0") && !strcontains(google_monitoring_dashboard.compute_dashboard.dashboard_json, "\"yPos\":0")
    error_message = "zero xPos/yPos must be stripped so the API's returned JSON matches."
  }

  # Stripping must not remove non-zero positions or corrupt the JSON.
  assert {
    condition     = can(jsondecode(google_monitoring_dashboard.compute_dashboard.dashboard_json)) && strcontains(google_monitoring_dashboard.compute_dashboard.dashboard_json, "\"xPos\":24")
    error_message = "normalisation must keep valid JSON and non-zero positions."
  }

  assert {
    condition     = !strcontains(google_monitoring_dashboard.compute_dashboard.dashboard_json, "\"title\":\"\"")
    error_message = "empty tile titles are dropped by the API and must not be sent."
  }
}

run "changing_a_tile_changes_the_planned_json" {
  command = plan

  variables {
    latency_threshold_ms = 750
  }

  assert {
    condition     = jsondecode(google_monitoring_dashboard.compute_dashboard.dashboard_json).mosaicLayout.tiles[0].widget.scorecard.thresholds[0].value == 750
    error_message = "a tile threshold change must reach the planned dashboard_json."
  }

  assert {
    condition     = strcontains(google_monitoring_dashboard.compute_dashboard.dashboard_json, "P99 \\u003e750 ms")
    error_message = "the tile label must follow the new threshold."
  }
}

run "removing_tiles_changes_the_planned_json" {
  command = plan

  variables {
    include_gen1_functions = false
  }

  assert {
    condition     = length(jsondecode(google_monitoring_dashboard.compute_dashboard.dashboard_json).mosaicLayout.tiles) == 2 + length(jsondecode(file("${path.module}/templates/cloud-run-tiles.json")))
    error_message = "dropping the Cloud Functions tiles must change the planned tile list."
  }
}
