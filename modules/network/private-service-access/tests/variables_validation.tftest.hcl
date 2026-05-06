# Variable validation tests for the network/private-service-access module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id  = "mock-project"
  vpc_network = "projects/mock-project/global/networks/mock-vpc"
}

# ── ip_version ─────────────────────────────────────────────────────────────────

run "accepts_ipv4" {
  command = plan

  variables {
    ip_version = "IPV4"
  }
}

run "accepts_ipv6" {
  command = plan

  variables {
    ip_version = "IPV6"
  }
}

run "rejects_invalid_ip_version" {
  command = plan

  expect_failures = [var.ip_version]

  variables {
    ip_version = "ipv4"
  }
}

# ── prefix_length ──────────────────────────────────────────────────────────────

run "accepts_prefix_length_16" {
  command = plan

  variables {
    prefix_length = 16
  }
}

run "accepts_boundary_prefix_length_8" {
  command = plan

  variables {
    prefix_length = 8
  }
}

run "accepts_boundary_prefix_length_29" {
  command = plan

  variables {
    prefix_length = 29
  }
}

run "rejects_prefix_length_too_small" {
  command = plan

  expect_failures = [var.prefix_length]

  variables {
    prefix_length = 7
  }
}

run "rejects_prefix_length_too_large" {
  command = plan

  expect_failures = [var.prefix_length]

  variables {
    prefix_length = 30
  }
}
