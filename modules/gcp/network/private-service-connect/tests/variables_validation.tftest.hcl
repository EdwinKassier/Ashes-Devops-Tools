# Variable validation tests for the network/private-service-connect module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id = "mock-project"
  name       = "pscendpoint"
  network    = "projects/mock-project/global/networks/mock-vpc"
  address    = "10.0.255.254"
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

# ── name (Google: 1-20 characters, lower-case letters and numbers, starts with a letter) ──

run "accepts_twenty_char_name" {
  command = plan

  variables {
    name = "a1234567890123456789"
  }
}

run "rejects_hyphenated_name" {
  command = plan

  expect_failures = [var.name]

  variables {
    name = "hub-vpc-core-psc"
  }
}

run "rejects_twenty_one_char_name" {
  command = plan

  expect_failures = [var.name]

  variables {
    name = "a12345678901234567890"
  }
}

run "rejects_name_starting_with_digit" {
  command = plan

  expect_failures = [var.name]

  variables {
    name = "1psc"
  }
}

# ── address (a single IPv4 address, outside every subnet range of the VPC) ──

run "rejects_cidr_as_address" {
  command = plan

  expect_failures = [var.address]

  variables {
    address = "10.0.255.0/24"
  }
}

run "rejects_ipv6_address" {
  command = plan

  expect_failures = [var.address]

  variables {
    address = "fd20::1"
  }
}

run "rejects_address_inside_a_subnet" {
  command = plan

  expect_failures = [var.address]

  variables {
    address           = "10.0.16.5"
    vpc_subnet_ranges = ["10.0.0.0/24", "10.0.16.0/24"]
  }
}

run "accepts_address_outside_subnets" {
  command = plan

  variables {
    address           = "10.0.255.254"
    vpc_subnet_ranges = ["10.0.0.0/24", "10.0.16.0/24", "100.64.0.0/14"]
  }
}
