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

# ── custom_rules action ────────────────────────────────────────────────────────

run "accepts_valid_custom_rule_action" {
  command = plan

  variables {
    custom_rules = {
      block-bad-ips = {
        action   = "deny"
        priority = 1000
        match_conditions = {
          versioned_expr = "SRC_IPS_V1"
          config         = { src_ip_ranges = ["192.0.2.0/24"] }
        }
      }
    }
  }
}

run "rejects_invalid_custom_rule_action" {
  command = plan

  expect_failures = [var.custom_rules]

  variables {
    custom_rules = {
      bad-rule = {
        action   = "block"
        priority = 1000
        match_conditions = {
          versioned_expr = "SRC_IPS_V1"
          config         = { src_ip_ranges = ["192.0.2.0/24"] }
        }
      }
    }
  }
}

# ── custom_rules match_conditions — CEL expr path ─────────────────────────────

run "accepts_cel_expr_match_condition" {
  # CEL expression match is mutually exclusive with versioned_expr.
  command = plan

  variables {
    custom_rules = {
      block-scrapers = {
        action      = "deny(403)"
        priority    = 500
        description = "Block known scraper user agents via CEL"
        match_conditions = {
          expr = "request.headers['user-agent'].lower().contains('scrapy')"
        }
      }
    }
  }
}

run "rejects_both_versioned_expr_and_cel_expr" {
  # Providing both match types in the same rule must fail validation.
  command = plan

  expect_failures = [var.custom_rules]

  variables {
    custom_rules = {
      conflicting-rule = {
        action   = "deny(403)"
        priority = 600
        match_conditions = {
          versioned_expr = "SRC_IPS_V1"
          config         = { src_ip_ranges = ["0.0.0.0/0"] }
          expr           = "request.headers['user-agent'].contains('bot')"
        }
      }
    }
  }
}

run "rejects_neither_versioned_expr_nor_cel_expr" {
  # Providing neither match type must also fail validation.
  command = plan

  expect_failures = [var.custom_rules]

  variables {
    custom_rules = {
      empty-match-rule = {
        action   = "deny(403)"
        priority = 700
        match_conditions = {}
      }
    }
  }
}
