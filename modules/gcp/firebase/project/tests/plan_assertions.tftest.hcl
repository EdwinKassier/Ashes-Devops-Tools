# Resource-assertion tests for the firebase/project module.
# Prior tests only planned; nothing asserted that the web-config bucket is
# private/encrypted or that the Apple API key is bundle-restricted
# (audit round-3 §D8 / finding #10). These attributes are config-derived and
# plan-knowable under mock_provider.

mock_provider "google" {}
mock_provider "google-beta" {}

variables {
  project_id = "mock-project"
  region     = "us-central1"
}

run "web_config_bucket_private_and_apple_key_restricted" {
  command = plan

  variables {
    apple_display_name = "My iOS App"
    apple_bundle_id    = "com.example.myapp"
    web_display_name   = "My Web App"
  }

  assert {
    condition     = google_storage_bucket.firebase_web_config[0].uniform_bucket_level_access == true
    error_message = "The Firebase web-config bucket must enforce uniform bucket-level access."
  }
  assert {
    condition     = google_storage_bucket.firebase_web_config[0].public_access_prevention == "enforced"
    error_message = "The Firebase web-config bucket must enforce public access prevention."
  }
  assert {
    condition     = contains(google_apikeys_key.apple[0].restrictions[0].ios_key_restrictions[0].allowed_bundle_ids, "com.example.myapp")
    error_message = "The Apple API key must be restricted to the configured bundle id."
  }
}

run "kms_key_encrypts_web_config_bucket" {
  command = plan

  variables {
    web_display_name = "My Web App"
    kms_key_name     = "projects/mock-project/locations/us-central1/keyRings/my-ring/cryptoKeys/my-key"
  }

  assert {
    condition     = google_storage_bucket.firebase_web_config[0].encryption[0].default_kms_key_name == var.kms_key_name
    error_message = "When kms_key_name is set, the web-config bucket must use it as the default CMEK."
  }
}
