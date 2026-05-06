# Variable validation tests for the network/packet-mirroring module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id        = "mock-project"
  name              = "test-mirroring"
  region            = "us-central1"
  network           = "projects/mock-project/global/networks/mock-vpc"
  collector_ilb_url = "projects/mock-project/regions/us-central1/forwardingRules/mock-ilb"
}

# ── name ───────────────────────────────────────────────────────────────────────

run "accepts_valid_name" {
  command = plan

  variables {
    name = "my-mirror-policy"
  }
}

run "rejects_name_starting_with_number" {
  command = plan

  expect_failures = [var.name]

  variables {
    name = "1invalid-name"
  }
}

run "rejects_name_with_uppercase" {
  command = plan

  expect_failures = [var.name]

  variables {
    name = "MyPolicy"
  }
}

# ── filter_direction ───────────────────────────────────────────────────────────

run "accepts_ingress_direction" {
  command = plan

  variables {
    filter_direction = "INGRESS"
  }
}

run "accepts_egress_direction" {
  command = plan

  variables {
    filter_direction = "EGRESS"
  }
}

run "accepts_both_direction" {
  command = plan

  variables {
    filter_direction = "BOTH"
  }
}

run "rejects_invalid_direction" {
  command = plan

  expect_failures = [var.filter_direction]

  variables {
    filter_direction = "ALL"
  }
}

# ── priority ───────────────────────────────────────────────────────────────────

run "accepts_priority_zero" {
  command = plan

  variables {
    priority = 0
  }
}

run "accepts_priority_1000" {
  command = plan

  variables {
    priority = 1000
  }
}

run "accepts_priority_max_65535" {
  command = plan

  variables {
    priority = 65535
  }
}

run "rejects_priority_above_65535" {
  command = plan

  expect_failures = [var.priority]

  variables {
    priority = 65536
  }
}

run "rejects_negative_priority" {
  command = plan

  expect_failures = [var.priority]

  variables {
    priority = -1
  }
}
