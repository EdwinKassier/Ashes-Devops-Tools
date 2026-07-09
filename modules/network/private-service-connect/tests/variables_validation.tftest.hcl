# Variable validation tests for the network/private-service-connect module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id = "mock-project"
  name       = "psc-endpoint"
  network    = "projects/mock-project/global/networks/mock-vpc"
}

# ── target ─────────────────────────────────────────────────────────────────────

run "accepts_all_apis_target" {
  command = plan

  variables {
    target = "all-apis"
  }
}

run "accepts_vpc_sc_target" {
  command = plan

  variables {
    target = "vpc-sc"
  }
}

run "accepts_default_target" {
  command = plan
  # Default is "all-apis" — verifies default is valid
}

run "creates_endpoint_with_resolved_target" {
  # The PSC endpoint (address + forwarding rule) is always created and the
  # forwarding rule target resolves from the google_targets map.
  command = plan

  variables {
    target = "all-apis"
  }

  assert {
    condition     = google_compute_global_forwarding_rule.psc_forwarding_rule.target == "all-apis"
    error_message = "forwarding rule target must resolve from the google_targets map"
  }

  assert {
    condition     = google_compute_global_address.psc_address.purpose == "PRIVATE_SERVICE_CONNECT"
    error_message = "the PSC IP address must be reserved unconditionally"
  }
}

run "rejects_invalid_target" {
  command = plan

  expect_failures = [var.target]

  variables {
    target = "all-api"
  }
}

run "rejects_service_attachment_uri" {
  command = plan

  expect_failures = [var.target]

  variables {
    target = "projects/my-project/regions/us-central1/serviceAttachments/my-attachment"
  }
}
