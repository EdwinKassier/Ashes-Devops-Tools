mock_provider "google" {}

# Verify that an INGRESS rule with allow rules plans successfully.
run "valid_ingress_allow_rule" {
  variables {
    project_id         = "my-project"
    firewall_rule_name = "allow-ssh"
    network            = "default"
    direction          = "INGRESS"
    allow_rules = [
      {
        protocol = "tcp"
        ports    = ["22"]
      }
    ]
    source_ranges = ["10.0.0.0/8"]
  }

  command = plan

  assert {
    condition     = google_compute_firewall.firewall_rule.direction == "INGRESS"
    error_message = "Expected direction to be INGRESS"
  }
}

# Verify that an EGRESS deny rule plans successfully.
run "valid_egress_deny_rule" {
  variables {
    project_id         = "my-project"
    firewall_rule_name = "deny-egress-all"
    network            = "default"
    direction          = "EGRESS"
    deny_rules = [
      {
        protocol = "all"
        ports    = null
      }
    ]
  }

  command = plan

  assert {
    condition     = google_compute_firewall.firewall_rule.direction == "EGRESS"
    error_message = "Expected direction to be EGRESS"
  }
}

# Verify that an invalid direction value is rejected.
run "invalid_direction_rejected" {
  variables {
    project_id         = "my-project"
    firewall_rule_name = "bad-rule"
    network            = "default"
    direction          = "BOTH"
  }

  command = plan

  expect_failures = [var.direction]
}

# Verify that an invalid firewall_rule_name is rejected.
run "invalid_firewall_rule_name_rejected" {
  variables {
    project_id         = "my-project"
    firewall_rule_name = "Bad_Name" # uppercase + underscore are invalid
    network            = "default"
    direction          = "INGRESS"
  }

  command = plan

  expect_failures = [var.firewall_rule_name]
}

# Verify that logging configuration is applied when enabled.
run "logging_enabled" {
  variables {
    project_id         = "my-project"
    firewall_rule_name = "allow-http-with-logging"
    network            = "default"
    allow_rules = [
      {
        protocol = "tcp"
        ports    = ["80", "443"]
      }
    ]
    source_ranges  = ["0.0.0.0/0"]
    enable_logging = true
    log_metadata   = "INCLUDE_ALL_METADATA"
  }

  command = plan

  assert {
    condition     = length(google_compute_firewall.firewall_rule.log_config) > 0
    error_message = "Expected log_config to be set when enable_logging is true"
  }
}
