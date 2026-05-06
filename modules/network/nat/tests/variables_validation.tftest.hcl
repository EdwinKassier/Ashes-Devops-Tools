# Variable validation tests for the nat module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id   = "mock-project"
  name         = "test-nat"
  region       = "europe-west1"
  network      = "projects/mock-project/global/networks/mock-vpc"
  router_name  = "test-router"
}

# ── nat_ip_allocate_option ─────────────────────────────────────────────────────

run "accepts_auto_only_allocation" {
  command = plan

  variables {
    nat_ip_allocate_option = "AUTO_ONLY"
  }
}

run "accepts_manual_only_allocation" {
  command = plan

  variables {
    nat_ip_allocate_option = "MANUAL_ONLY"
  }
}

run "rejects_invalid_nat_ip_allocate_option" {
  command = plan

  expect_failures = [var.nat_ip_allocate_option]

  variables {
    nat_ip_allocate_option = "DYNAMIC"
  }
}

# ── source_subnetwork_ip_ranges_to_nat ─────────────────────────────────────────

run "accepts_all_subnetworks_all_ip_ranges" {
  command = plan

  variables {
    source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  }
}

run "accepts_primary_ip_ranges_only" {
  command = plan

  variables {
    source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_PRIMARY_IP_RANGES"
  }
}

run "rejects_invalid_source_subnetwork_option" {
  command = plan

  expect_failures = [var.source_subnetwork_ip_ranges_to_nat]

  variables {
    source_subnetwork_ip_ranges_to_nat = "SELECTED_SUBNETWORKS"
  }
}

# ── log_filter ─────────────────────────────────────────────────────────────────

run "accepts_errors_only_log_filter" {
  command = plan

  variables {
    log_filter = "ERRORS_ONLY"
  }
}

run "accepts_all_log_filter" {
  command = plan

  variables {
    log_filter = "ALL"
  }
}

run "rejects_invalid_log_filter" {
  command = plan

  expect_failures = [var.log_filter]

  variables {
    log_filter = "NONE"
  }
}
