# Input validation for stages/net-spoke (mock providers, no credentials).

mock_provider "google" {
  mock_data "google_compute_zones" {
    defaults = {
      names = ["us-central1-a"]
    }
  }
}
mock_provider "google-beta" {}

variables {
  project_id     = "mock-host-project"
  project_prefix = "mock-dev"
  network = {
    name           = "mock-dev-vpc"
    cidr_block     = "10.10.0.0/16"
    explicit_zones = ["us-central1-a"]
  }
}

run "accepts_valid_inputs" {
  command = plan
}

run "rejects_invalid_project_prefix" {
  command = plan
  variables {
    project_prefix = "Mock_Dev"
  }
  expect_failures = [var.project_prefix]
}

run "rejects_cidr_with_host_bits" {
  command = plan
  variables {
    network = { name = "mock-dev-vpc", cidr_block = "10.10.1.0/16" }
  }
  expect_failures = [var.network]
}

run "rejects_invalid_explicit_zone" {
  command = plan
  variables {
    network = { name = "mock-dev-vpc", cidr_block = "10.10.0.0/16", explicit_zones = ["us-central1"] }
  }
  expect_failures = [var.network]
}

run "rejects_invalid_nat_log_filter" {
  command = plan
  variables {
    nat = { log_filter = "EVERYTHING" }
  }
  expect_failures = [var.nat]
}

run "rejects_out_of_range_psa_prefix" {
  command = plan
  variables {
    private_service_access = { prefix_length = 8 }
  }
  expect_failures = [var.private_service_access]
}

run "rejects_unknown_psc_target" {
  command = plan
  variables {
    private_service_connect = { target = "some-api" }
  }
  expect_failures = [var.private_service_connect]
}

run "rejects_invalid_owasp_sensitivity" {
  command = plan
  variables {
    edge = { cloud_armor = { owasp_sensitivity = 7 } }
  }
  expect_failures = [var.edge]
}

run "rejects_flow_log_export_without_destination" {
  command = plan
  variables {
    flow_logs_export = { enabled = true }
  }
  expect_failures = [var.flow_logs_export]
}

run "rejects_invalid_firewall_mode" {
  command = plan

  variables {
    firewall_mode = "tags"
  }

  expect_failures = [var.firewall_mode]
}

# ── connectivity / ncc ─────────────────────────────────────────────────────────

run "rejects_unknown_connectivity" {
  command = plan

  variables {
    connectivity = "transit"
  }

  expect_failures = [var.connectivity]
}

run "rejects_ncc_without_hub_id" {
  command = plan

  variables {
    connectivity = "ncc"
  }

  expect_failures = [var.ncc]
}

run "rejects_center_group_for_spoke" {
  command = plan

  variables {
    connectivity = "ncc"
    ncc = {
      hub_id = "projects/mock-hub-project/locations/global/hubs/mock-hub"
      group  = "center"
    }
  }

  expect_failures = [var.ncc]
}
