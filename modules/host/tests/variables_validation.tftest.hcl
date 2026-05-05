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
