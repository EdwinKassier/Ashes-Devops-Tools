# Variable validation tests for the governance/tags module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

# Default valid inputs shared across runs that don't supply their own.
variables {
  org_id = "123456789"
  tags = {
    environment = {
      values      = ["dev", "prod"]
      description = "Deployment environment tier"
    }
  }
}

# ── org_id ─────────────────────────────────────────────────────────────────────

run "accepts_valid_numeric_org_id" {
  command = plan
}

run "rejects_org_id_with_prefix" {
  command         = plan
  expect_failures = [var.org_id]
  variables {
    org_id = "organizations/123456789"
  }
}

run "rejects_non_numeric_org_id" {
  command         = plan
  expect_failures = [var.org_id]
  variables {
    org_id = "abc123"
  }
}

# ── tags — structure ──────────────────────────────────────────────────────────

run "accepts_tags_with_description" {
  command = plan
  variables {
    tags = {
      "environment" = {
        values      = ["dev", "staging", "prod"]
        description = "Deployment environment tier"
      }
      "cost-center" = {
        values = ["engineering", "marketing"]
        # description omitted — defaults to "Managed by Terraform"
      }
    }
  }
}

run "accepts_tags_without_description" {
  # Omitting description should not fail; it defaults to "Managed by Terraform".
  command = plan
  variables {
    tags = {
      "team" = {
        values = ["platform", "backend"]
      }
    }
  }
}

run "rejects_empty_tags" {
  command         = plan
  expect_failures = [var.tags]
  variables {
    tags = {}
  }
}

# ── tags — key format ─────────────────────────────────────────────────────────

run "rejects_key_starting_with_digit" {
  command         = plan
  expect_failures = [var.tags]
  variables {
    tags = {
      "1environment" = { values = ["dev"] }
    }
  }
}

run "rejects_key_with_uppercase" {
  command         = plan
  expect_failures = [var.tags]
  variables {
    tags = {
      "Environment" = { values = ["dev"] }
    }
  }
}

run "rejects_key_with_spaces" {
  command         = plan
  expect_failures = [var.tags]
  variables {
    tags = {
      "env name" = { values = ["dev"] }
    }
  }
}

# ── tags — value format ───────────────────────────────────────────────────────

run "rejects_value_starting_with_digit" {
  command         = plan
  expect_failures = [var.tags]
  variables {
    tags = {
      "environment" = { values = ["1dev"] }
    }
  }
}

run "rejects_value_with_uppercase" {
  command         = plan
  expect_failures = [var.tags]
  variables {
    tags = {
      "environment" = { values = ["Dev"] }
    }
  }
}
