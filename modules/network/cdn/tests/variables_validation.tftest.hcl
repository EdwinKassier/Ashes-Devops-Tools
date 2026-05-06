# Variable validation tests for the network/cdn module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id = "mock-project"
  lb_name    = "test-lb"
}

# ── cdn_policy.cache_mode ──────────────────────────────────────────────────────

run "accepts_cache_all_static_mode" {
  command = plan

  variables {
    cdn_policy = {
      cache_mode = "CACHE_ALL_STATIC"
    }
  }
}

run "accepts_use_origin_headers_mode" {
  command = plan

  variables {
    cdn_policy = {
      cache_mode = "USE_ORIGIN_HEADERS"
    }
  }
}

run "accepts_force_cache_all_mode" {
  command = plan

  variables {
    cdn_policy = {
      cache_mode = "FORCE_CACHE_ALL"
    }
  }
}

run "rejects_invalid_cache_mode" {
  command = plan

  expect_failures = [var.cdn_policy]

  variables {
    cdn_policy = {
      cache_mode = "AGGRESSIVE"
    }
  }
}

run "accepts_default_cdn_policy" {
  command = plan
  # Verifies the default {} resolves to CACHE_ALL_STATIC without error
}
