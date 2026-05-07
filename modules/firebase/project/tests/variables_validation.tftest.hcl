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
    apple_display_name   = "My iOS App"
    apple_bundle_id      = "com.example.myapp"
    android_display_name = "My Android App"
    android_package_name = "com.example.myapp"
    web_display_name     = "My Web App"
  }
}

run "accepts_kms_key_for_web_config_bucket" {
  command = plan

  variables {
    kms_key_name = "projects/mock-project/locations/us-central1/keyRings/my-ring/cryptoKeys/my-key"
  }
}

# ── kms_key_name ───────────────────────────────────────────────────────────────

run "rejects_invalid_kms_key_name" {
  command         = plan
  expect_failures = [var.kms_key_name]
  variables {
    kms_key_name = "my-ring/my-key"
  }
}

# ── apple_team_id ──────────────────────────────────────────────────────────────

run "accepts_valid_apple_team_id" {
  command = plan
  variables {
    apple_team_id = "ABCDE12345"
  }
}

run "rejects_lowercase_apple_team_id" {
  command         = plan
  expect_failures = [var.apple_team_id]
  variables {
    apple_team_id = "abcde12345"
  }
}

run "rejects_short_apple_team_id" {
  command         = plan
  expect_failures = [var.apple_team_id]
  variables {
    apple_team_id = "ABCDE1234"
  }
}

# ── android_sha1_hashes ────────────────────────────────────────────────────────

run "accepts_valid_sha1_hash" {
  command = plan
  variables {
    android_sha1_hashes = ["aabbccddeeff00112233445566778899aabbccdd"]
  }
}

run "accepts_colon_separated_sha1_hash" {
  command = plan
  variables {
    android_sha1_hashes = ["AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD"]
  }
}

run "rejects_invalid_sha1_hash_length" {
  command         = plan
  expect_failures = [var.android_sha1_hashes]
  variables {
    android_sha1_hashes = ["aabbccdd"]
  }
}

# ── android_sha256_hashes ──────────────────────────────────────────────────────

run "accepts_valid_sha256_hash" {
  command = plan
  variables {
    android_sha256_hashes = ["aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899"]
  }
}

run "rejects_invalid_sha256_hash_length" {
  command         = plan
  expect_failures = [var.android_sha256_hashes]
  variables {
    android_sha256_hashes = ["aabbccdd"]
  }
}
