# Variable validation tests for the vpc-sc module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  organization_id = "organizations/123456789"
  perimeter_name  = "test_perimeter"
  perimeter_title = "Test Perimeter"
  # access_policy_name must be a bare numeric ID — no "accessPolicies/" prefix.
  access_policy_name = "1234567890"
}

# ── organization_id ────────────────────────────────────────────────────────────

run "accepts_valid_organization_id" {
  command = plan

  variables {
    organization_id = "organizations/123456789"
  }
}

run "rejects_organization_id_without_prefix" {
  command = plan

  expect_failures = [var.organization_id]

  variables {
    organization_id = "123456789"
  }
}

run "rejects_organization_id_with_letters" {
  command = plan

  expect_failures = [var.organization_id]

  variables {
    organization_id = "organizations/my-org"
  }
}

# ── access_policy_name ────────────────────────────────────────────────────────

run "accepts_bare_numeric_access_policy_name" {
  command = plan

  variables {
    access_policy_name = "9876543210"
  }
}

run "rejects_prefixed_access_policy_name" {
  command = plan

  expect_failures = [var.access_policy_name]

  variables {
    access_policy_name = "accessPolicies/1234567890"
  }
}

# ── perimeter_name ─────────────────────────────────────────────────────────────

run "accepts_valid_perimeter_name" {
  command = plan

  variables {
    perimeter_name = "prod_perimeter"
  }
}

run "accepts_perimeter_name_with_numbers" {
  command = plan

  variables {
    perimeter_name = "perimeter01"
  }
}

run "rejects_perimeter_name_starting_with_digit" {
  command = plan

  expect_failures = [var.perimeter_name]

  variables {
    perimeter_name = "1invalid"
  }
}

run "rejects_perimeter_name_with_hyphens" {
  command = plan

  expect_failures = [var.perimeter_name]

  variables {
    perimeter_name = "bad-name"
  }
}

# ── perimeter_type ─────────────────────────────────────────────────────────────

run "accepts_perimeter_type_regular" {
  command = plan

  variables {
    perimeter_type = "PERIMETER_TYPE_REGULAR"
  }
}

run "accepts_perimeter_type_bridge" {
  command = plan

  variables {
    perimeter_type = "PERIMETER_TYPE_BRIDGE"
  }
}

run "rejects_invalid_perimeter_type" {
  command = plan

  expect_failures = [var.perimeter_type]

  variables {
    perimeter_type = "INVALID_TYPE"
  }
}
