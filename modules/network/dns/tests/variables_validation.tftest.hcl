# Variable validation tests for the dns module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id = "mock-project"
  zone_name  = "test-zone"
  dns_name   = "internal.example.com."
}

# ── dns_name ───────────────────────────────────────────────────────────────────

run "accepts_dns_name_with_trailing_dot" {
  command = plan

  variables {
    dns_name = "internal.company.com."
  }
}

run "accepts_subdomain_dns_name" {
  command = plan

  variables {
    dns_name = "services.internal.example.com."
  }
}

run "rejects_dns_name_without_trailing_dot" {
  command = plan

  expect_failures = [var.dns_name]

  variables {
    dns_name = "internal.example.com"
  }
}

# ── visibility ─────────────────────────────────────────────────────────────────

run "accepts_private_visibility" {
  command = plan

  variables {
    visibility = "private"
  }
}

run "accepts_public_visibility" {
  command = plan

  variables {
    visibility = "public"
  }
}

run "rejects_invalid_visibility" {
  command = plan

  expect_failures = [var.visibility]

  variables {
    visibility = "internal"
  }
}
