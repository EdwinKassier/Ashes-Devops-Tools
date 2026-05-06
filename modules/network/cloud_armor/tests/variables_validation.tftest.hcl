# Variable validation tests for the cloud_armor module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id  = "mock-project"
  policy_name = "test-policy"
}

# ── default_rule_action ────────────────────────────────────────────────────────

run "accepts_default_rule_allow" {
  command = plan

  variables {
    default_rule_action = "allow"
  }
}

run "accepts_default_rule_deny" {
  command = plan

  variables {
    default_rule_action = "deny"
  }
}

run "rejects_invalid_default_rule_action" {
  command = plan

  expect_failures = [var.default_rule_action]

  variables {
    default_rule_action = "block"
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
