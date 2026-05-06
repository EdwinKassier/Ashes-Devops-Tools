# Variable validation tests for the firebase/project module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}
mock_provider "google-beta" {}

variables {
  project_id = "mock-project"
}

# ── smoke test ─────────────────────────────────────────────────────────────────

run "accepts_minimal_required_inputs" {
  command = plan
}

run "accepts_all_app_platforms_configured" {
  command = plan

  variables {
    apple_display_name  = "My iOS App"
    apple_bundle_id     = "com.example.myapp"
    android_display_name = "My Android App"
    android_package_name = "com.example.myapp"
    web_display_name    = "My Web App"
  }
}

run "accepts_kms_key_for_web_config_bucket" {
  command = plan

  variables {
    kms_key_name = "projects/mock-project/locations/us-central1/keyRings/my-ring/cryptoKeys/my-key"
  }
}
