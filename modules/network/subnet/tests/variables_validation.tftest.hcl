# Variable validation tests for the subnet module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id    = "mock-project"
  subnet_name   = "test-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = "europe-west1"
  network       = "projects/mock-project/global/networks/mock-vpc"
}

# ── ip_cidr_range ──────────────────────────────────────────────────────────────

run "accepts_valid_cidr_range" {
  command = plan

  variables {
    ip_cidr_range = "10.128.0.0/20"
  }
}

run "rejects_invalid_cidr_format" {
  command = plan

  expect_failures = [var.ip_cidr_range]

  variables {
    ip_cidr_range = "not-a-cidr"
  }
}

run "rejects_cidr_with_host_bits_set" {
  command = plan

  expect_failures = [var.ip_cidr_range]

  variables {
    ip_cidr_range = "10.0.1.128/24"
  }
}

# ── region ─────────────────────────────────────────────────────────────────────

run "accepts_valid_region" {
  command = plan

  variables {
    region = "us-central1"
  }
}

run "accepts_multi_part_region" {
  command = plan

  variables {
    region = "northamerica-northeast1"
  }
}

run "rejects_invalid_region_format" {
  command = plan

  expect_failures = [var.region]

  variables {
    region = "EUROPE-WEST1"
  }
}

# ── log_config_aggregation_interval ───────────────────────────────────────────

run "accepts_valid_aggregation_interval" {
  command = plan

  variables {
    log_config_aggregation_interval = "INTERVAL_1_MIN"
  }
}

run "rejects_invalid_aggregation_interval" {
  command = plan

  expect_failures = [var.log_config_aggregation_interval]

  variables {
    log_config_aggregation_interval = "INTERVAL_2_MIN"
  }
}

# ── log_config_metadata ────────────────────────────────────────────────────────

run "accepts_exclude_all_metadata" {
  command = plan

  variables {
    log_config_metadata = "EXCLUDE_ALL_METADATA"
  }
}

run "rejects_invalid_metadata_value" {
  command = plan

  expect_failures = [var.log_config_metadata]

  variables {
    log_config_metadata = "INCLUDE_SOME_METADATA"
  }
}

# ── purpose ────────────────────────────────────────────────────────────────────

run "accepts_null_purpose" {
  command = plan

  variables {
    purpose = null
  }
}

run "accepts_regional_managed_proxy_purpose" {
  command = plan

  variables {
    purpose = "REGIONAL_MANAGED_PROXY"
    role    = "ACTIVE"
  }
}

run "rejects_invalid_purpose" {
  command = plan

  expect_failures = [var.purpose]

  variables {
    purpose = "UNKNOWN_PURPOSE"
  }
}

# ── role ───────────────────────────────────────────────────────────────────────

run "accepts_active_role" {
  command = plan

  variables {
    role = "ACTIVE"
  }
}

run "accepts_null_role" {
  command = plan

  variables {
    role = null
  }
}

run "rejects_invalid_role" {
  command = plan

  expect_failures = [var.role]

  variables {
    role = "PRIMARY"
  }
}
