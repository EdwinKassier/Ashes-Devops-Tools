# Variable validation tests for the host module.
# All runs use mock_provider so no GCP credentials are required.
# Tests use expect_failures — variable validation blocks fire before resource
# evaluation, so these pass regardless of data source mock behaviour.

mock_provider "google" {
  mock_data "google_compute_zones" {
    defaults = {
      names = ["europe-west1-b", "europe-west1-c", "europe-west1-d"]
    }
  }
}
mock_provider "google-beta" {}

# Minimum required variables shared across all runs
variables {
  project_id     = "mock-project"
  project_prefix = "mock"
  vpc_cidr_block = "10.0.0.0/16"
}

# ── vpc_cidr_block ─────────────────────────────────────────────────────────────

run "accepts_valid_cidr_block" {
  command = plan

  variables {
    vpc_cidr_block = "10.128.0.0/16"
  }
}

run "rejects_invalid_cidr_block" {
  command = plan

  expect_failures = [var.vpc_cidr_block]

  variables {
    vpc_cidr_block = "not-a-cidr"
  }
}

run "rejects_cidr_with_host_bits_set" {
  command = plan

  expect_failures = [var.vpc_cidr_block]

  variables {
    vpc_cidr_block = "10.0.1.0/8"
  }
}

# ── psa_prefix_length ──────────────────────────────────────────────────────────

run "accepts_psa_prefix_at_minimum" {
  command = plan

  variables {
    psa_prefix_length = 16
  }
}

run "accepts_psa_prefix_at_maximum" {
  command = plan

  variables {
    psa_prefix_length = 29
  }
}

run "rejects_psa_prefix_below_minimum" {
  command = plan

  expect_failures = [var.psa_prefix_length]

  variables {
    psa_prefix_length = 15
  }
}

run "rejects_psa_prefix_above_maximum" {
  command = plan

  expect_failures = [var.psa_prefix_length]

  variables {
    psa_prefix_length = 30
  }
}

# ── log_config_flow_sampling ───────────────────────────────────────────────────

run "accepts_flow_sampling_at_zero" {
  command = plan

  variables {
    log_config_flow_sampling = 0.0
  }
}

run "accepts_flow_sampling_at_one" {
  command = plan

  variables {
    log_config_flow_sampling = 1.0
  }
}

run "rejects_flow_sampling_above_one" {
  command = plan

  expect_failures = [var.log_config_flow_sampling]

  variables {
    log_config_flow_sampling = 1.1
  }
}

run "rejects_flow_sampling_negative" {
  command = plan

  expect_failures = [var.log_config_flow_sampling]

  variables {
    log_config_flow_sampling = -0.1
  }
}

# ── owasp_sensitivity ──────────────────────────────────────────────────────────

run "accepts_owasp_sensitivity_boundary_low" {
  command = plan

  variables {
    owasp_sensitivity = 1
  }
}

run "accepts_owasp_sensitivity_boundary_high" {
  command = plan

  variables {
    owasp_sensitivity = 4
  }
}

run "rejects_owasp_sensitivity_zero" {
  command = plan

  expect_failures = [var.owasp_sensitivity]

  variables {
    owasp_sensitivity = 0
  }
}

run "rejects_owasp_sensitivity_five" {
  command = plan

  expect_failures = [var.owasp_sensitivity]

  variables {
    owasp_sensitivity = 5
  }
}

# ── vpn_tunnel_count ───────────────────────────────────────────────────────────

run "accepts_vpn_tunnel_count_one" {
  command = plan

  variables {
    vpn_tunnel_count = 1
  }
}

run "accepts_vpn_tunnel_count_two" {
  command = plan

  variables {
    vpn_tunnel_count = 2
  }
}

run "rejects_vpn_tunnel_count_zero" {
  command = plan

  expect_failures = [var.vpn_tunnel_count]

  variables {
    vpn_tunnel_count = 0
  }
}

run "rejects_vpn_tunnel_count_three" {
  command = plan

  expect_failures = [var.vpn_tunnel_count]

  variables {
    vpn_tunnel_count = 3
  }
}

# ── integrated_nat_ip_allocate_option ─────────────────────────────────────────

run "rejects_invalid_nat_ip_allocate_option" {
  command = plan

  expect_failures = [var.integrated_nat_ip_allocate_option]

  variables {
    integrated_nat_ip_allocate_option = "INVALID_VALUE"
  }
}

# ── integrated_nat_log_filter ─────────────────────────────────────────────────

run "rejects_invalid_nat_log_filter" {
  command = plan

  expect_failures = [var.integrated_nat_log_filter]

  variables {
    integrated_nat_log_filter = "ALL_TRAFFIC_TYPO"
  }
}

# ── project_id format ─────────────────────────────────────────────────────────

run "rejects_project_id_too_short" {
  command = plan

  expect_failures = [var.project_id]

  variables {
    project_id = "ab"
  }
}

run "rejects_project_id_with_uppercase" {
  command = plan

  expect_failures = [var.project_id]

  variables {
    project_id = "My-Project-ID"
  }
}

run "rejects_project_id_starting_with_digit" {
  command = plan

  expect_failures = [var.project_id]

  variables {
    project_id = "1invalid-project"
  }
}

run "accepts_valid_project_id" {
  command = plan

  variables {
    project_id = "my-valid-project-id"
  }
}

# ── region format ─────────────────────────────────────────────────────────────

run "rejects_invalid_region_format" {
  command = plan

  expect_failures = [var.region]

  variables {
    region = "us_central_1"
  }
}

run "accepts_valid_region" {
  command = plan

  variables {
    region = "europe-west1"
  }
}

# ── enable_networking = false requires existing_network_id ────────────────────
# When enable_networking = false, module.vpc[0] is not created.
# The existing_network_id must be provided or resources referencing the VPC will fail.
# This is a documentation/contract test — not a variable validation block failure.

run "accepts_enable_networking_false_with_existing_network" {
  command = plan

  variables {
    enable_networking       = false
    existing_network_id     = "projects/my-project/global/networks/existing-vpc"
    existing_network_self_link = "https://www.googleapis.com/compute/v1/projects/my-project/global/networks/existing-vpc"
  }
}

# ── project_prefix format ────────────────────────────────────────────────────

run "rejects_project_prefix_starting_with_digit" {
  command = plan

  expect_failures = [var.project_prefix]

  variables {
    project_prefix = "1invalid"
  }
}

run "rejects_project_prefix_with_uppercase" {
  command = plan

  expect_failures = [var.project_prefix]

  variables {
    project_prefix = "Invalid-Prefix"
  }
}

run "accepts_valid_project_prefix" {
  command = plan

  variables {
    project_prefix = "ashes-dev"
  }
}
