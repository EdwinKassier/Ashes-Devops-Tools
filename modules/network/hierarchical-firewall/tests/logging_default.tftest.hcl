# Regression test: a rule that omits enable_logging must fall back to the
# module-level var.enable_logging default. Previously the object default of
# false made the per-rule value never-unset, so the fallback was dead code.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  parent      = "organizations/123456789"
  policy_name = "test-policy"
}

run "rule_without_logging_inherits_module_default" {
  command = plan

  variables {
    enable_logging = true
    rules = [
      {
        priority  = 1000
        action    = "allow"
        direction = "INGRESS"
        # enable_logging intentionally omitted → must inherit var.enable_logging.
        layer4_configs = [
          { ip_protocol = "tcp", ports = ["443"] }
        ]
        src_ip_ranges = ["10.0.0.0/8"]
      }
    ]
  }

  assert {
    condition     = length(google_compute_firewall_policy_rule.rules) > 0
    error_message = "expected at least one firewall policy rule to be planned"
  }

  assert {
    condition     = google_compute_firewall_policy_rule.rules["1000"].enable_logging == true
    error_message = "a rule omitting enable_logging must inherit the module-level enable_logging default (true)"
  }
}
