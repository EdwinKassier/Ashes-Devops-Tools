# Plan assertions for the vpc-sc module: verify the regular service perimeter is
# planned with the caller-supplied title, and that dry-run wiring is honored.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  organization_id    = "organizations/123456789"
  perimeter_name     = "test_perimeter"
  perimeter_title    = "Test Perimeter"
  access_policy_name = "1234567890"
}

run "regular_perimeter_planned_with_title" {
  command = plan

  assert {
    condition     = length(google_access_context_manager_service_perimeter.perimeter) == 1
    error_message = "A regular (PERIMETER_TYPE_REGULAR) perimeter must be planned by default."
  }

  assert {
    condition     = google_access_context_manager_service_perimeter.perimeter[0].title == var.perimeter_title
    error_message = "Perimeter title must be the caller-supplied perimeter_title."
  }
}

run "dry_run_toggles_explicit_dry_run_spec" {
  command = plan

  variables {
    enable_dry_run = true
  }

  assert {
    condition     = google_access_context_manager_service_perimeter.perimeter[0].use_explicit_dry_run_spec == true
    error_message = "enable_dry_run = true must set use_explicit_dry_run_spec on the perimeter."
  }
}
