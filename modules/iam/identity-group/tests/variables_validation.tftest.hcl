# Variable validation tests for the iam/identity_group module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  customer_id = "C01abc234"
}

# ── customer_id ────────────────────────────────────────────────────────────────

run "accepts_alphanumeric_customer_id" {
  command = plan

  variables {
    customer_id = "C01abc234"
  }
}

run "accepts_uppercase_customer_id" {
  command = plan

  variables {
    customer_id = "ABCDEF123"
  }
}

run "rejects_customer_id_with_hyphens" {
  command = plan

  expect_failures = [var.customer_id]

  variables {
    customer_id = "C01-abc234"
  }
}

run "rejects_customer_id_with_spaces" {
  command = plan

  expect_failures = [var.customer_id]

  variables {
    customer_id = "C01 abc"
  }
}
