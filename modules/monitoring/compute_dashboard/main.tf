locals {
  # Read JSON content as strings; the ternary is valid since both branches are strings.
  # jsondecode on a computed string returns dynamic, which concat accepts without type errors.
  cf_tiles_json   = var.include_gen1_functions ? file("${path.module}/templates/cloud-functions-tiles.json") : "[]"
  dashboard_tiles = concat(
    jsondecode(file("${path.module}/templates/cloud-run-tiles.json")),
    jsondecode(local.cf_tiles_json)
  )
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
    # The API may return slightly different JSON than what was sent
    ignore_changes = [dashboard_json]
  }
}
