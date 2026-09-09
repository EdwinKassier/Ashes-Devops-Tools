# Plan assertions for the network-firewall module: verify the firewall rule is planned
# with the caller-supplied identity/direction, and that per-rule logging is opt-in
# (default off at this primitive; composing stages enable it — audit L4).
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

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

run "firewall_rule_wired_logging_off_by_default" {
  command = plan

  assert {
    condition     = google_compute_firewall.firewall_rule.name == var.firewall_rule_name
    error_message = "Firewall rule name must be the caller-supplied firewall_rule_name."
  }

  assert {
    condition     = google_compute_firewall.firewall_rule.network == var.network
    error_message = "Firewall rule must attach to the caller-supplied network."
  }

  assert {
    condition     = length(google_compute_firewall.firewall_rule.log_config) == 0
    error_message = "Per-rule logging is opt-in; no log_config must be planned by default."
  }
}

run "logging_enabled_when_opted_in" {
  command = plan

  variables {
    enable_logging = true
  }

  assert {
    condition     = length(google_compute_firewall.firewall_rule.log_config) == 1
    error_message = "enable_logging = true must attach a log_config to the firewall rule."
  }
}
