# Variable validation tests for the network/vpc-peering module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id   = "mock-project"
  peering_name = "test-peering"
  network      = "projects/mock-project/global/networks/mock-vpc"
  peer_network = "projects/peer-project/global/networks/peer-vpc"
}

# ── stack_type ─────────────────────────────────────────────────────────────────

run "accepts_ipv4_only_stack_type" {
  command = plan

  variables {
    stack_type = "IPV4_ONLY"
  }
}

run "accepts_ipv4_ipv6_stack_type" {
  command = plan

  variables {
    stack_type = "IPV4_IPV6"
  }
}

run "rejects_invalid_stack_type" {
  command = plan

  expect_failures = [var.stack_type]

  variables {
    stack_type = "IPV6_ONLY"
  }
}
