# Variable validation tests for the network/hierarchical-firewall module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  parent      = "organizations/123456789"
  policy_name = "test-policy"
}

# ── parent ─────────────────────────────────────────────────────────────────────

run "accepts_organizations_parent" {
  command = plan

  variables {
    parent = "organizations/123456789"
  }
}

run "accepts_folders_parent" {
  command = plan

  variables {
    parent = "folders/987654321"
  }
}

run "rejects_parent_without_id" {
  command = plan

  expect_failures = [var.parent]

  variables {
    parent = "organizations/"
  }
}

run "rejects_parent_with_invalid_resource_type" {
  command = plan

  expect_failures = [var.parent]

  variables {
    parent = "projects/my-project"
  }
}

# ── policy_name ────────────────────────────────────────────────────────────────

run "accepts_valid_policy_name" {
  command = plan

  variables {
    policy_name = "org-baseline-policy"
  }
}

run "rejects_policy_name_starting_with_number" {
  command = plan

  expect_failures = [var.policy_name]

  variables {
    policy_name = "1-invalid-name"
  }
}

run "rejects_policy_name_with_uppercase" {
  command = plan

  expect_failures = [var.policy_name]

  variables {
    policy_name = "Invalid-Policy"
  }
}

# ── rules.action ───────────────────────────────────────────────────────────────

run "accepts_allow_rule_action" {
  command = plan

  variables {
    rules = [{
      priority  = 1000
      action    = "allow"
      direction = "INGRESS"
      layer4_configs = [{ ip_protocol = "tcp" }]
    }]
  }
}

run "accepts_deny_rule_action" {
  command = plan

  variables {
    rules = [{
      priority  = 2000
      action    = "deny"
      direction = "EGRESS"
      layer4_configs = [{ ip_protocol = "udp" }]
    }]
  }
}

run "accepts_goto_next_rule_action" {
  command = plan

  variables {
    rules = [{
      priority  = 3000
      action    = "goto_next"
      direction = "INGRESS"
      layer4_configs = [{ ip_protocol = "all" }]
    }]
  }
}

run "rejects_invalid_rule_action" {
  command = plan

  expect_failures = [var.rules]

  variables {
    rules = [{
      priority  = 1000
      action    = "DROP"
      direction = "INGRESS"
      layer4_configs = [{ ip_protocol = "tcp" }]
    }]
  }
}

# ── rules.direction ────────────────────────────────────────────────────────────

run "accepts_ingress_direction" {
  command = plan

  variables {
    rules = [{
      priority  = 1000
      action    = "allow"
      direction = "INGRESS"
      layer4_configs = [{ ip_protocol = "tcp" }]
    }]
  }
}

run "accepts_egress_direction" {
  command = plan

  variables {
    rules = [{
      priority  = 1000
      action    = "allow"
      direction = "EGRESS"
      layer4_configs = [{ ip_protocol = "tcp" }]
    }]
  }
}

run "rejects_invalid_direction" {
  command = plan

  expect_failures = [var.rules]

  variables {
    rules = [{
      priority  = 1000
      action    = "allow"
      direction = "BOTH"
      layer4_configs = [{ ip_protocol = "tcp" }]
    }]
  }
}
