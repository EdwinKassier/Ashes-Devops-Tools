# Regression test: the dashboard console URL must be built from the BARE
# dashboard id, not the full resource name (projects/N/dashboards/X).
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

# Force the dashboard id to the full resource-name form the API returns so the
# output's prefix-stripping is actually exercised.
override_resource {
  target = google_monitoring_dashboard.compute_dashboard
  values = {
    id = "projects/123456789/dashboards/abc-123-def"
  }
}

variables {
  project_id = "mock-project"
}

run "console_url_uses_bare_dashboard_id" {
  # apply so the overridden computed `id` resolves; mock_provider makes this
  # credential-free.
  command = apply

  assert {
    condition     = output.dashboard_console_url == "https://console.cloud.google.com/monitoring/dashboards/builder/abc-123-def?project=mock-project"
    error_message = "console URL must use the bare dashboard id, not the projects/N/dashboards/ resource-name prefix"
  }

  assert {
    condition     = !strcontains(output.dashboard_console_url, "projects/123456789/dashboards")
    error_message = "console URL must not contain the projects/.../dashboards/ resource-name prefix"
  }
}
