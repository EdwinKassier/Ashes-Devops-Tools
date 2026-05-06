# Variable validation tests for the iam/organization module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  domain      = "example.com"
  project_id  = "mock-project"
  customer_id = "C0abc123"
}

# ── customer_id ────────────────────────────────────────────────────────────────

run "accepts_alphanumeric_customer_id" {
  command = plan

  variables {
    customer_id = "C0abc123"
  }
}

run "rejects_customer_id_with_hyphens" {
  command = plan

  expect_failures = [var.customer_id]

  variables {
    customer_id = "C0-abc123"
  }
}

# ── org_admin_members ──────────────────────────────────────────────────────────

run "accepts_valid_org_admin_member_prefixes" {
  command = plan

  variables {
    org_admin_members = [
      "user:admin@example.com",
      "group:admins@example.com",
      "serviceAccount:sa@proj.iam.gserviceaccount.com",
      "domain:example.com",
    ]
  }
}

run "accepts_empty_org_admin_members" {
  command = plan

  variables {
    org_admin_members = []
  }
}

run "rejects_org_admin_member_without_prefix" {
  command = plan

  expect_failures = [var.org_admin_members]

  variables {
    org_admin_members = ["admin@example.com"]
  }
}

# ── billing_admin_members ──────────────────────────────────────────────────────

run "accepts_valid_billing_admin_member_prefixes" {
  command = plan

  variables {
    billing_admin_members = [
      "user:billing@example.com",
      "group:billing-admins@example.com",
    ]
  }
}

run "rejects_billing_admin_member_without_prefix" {
  command = plan

  expect_failures = [var.billing_admin_members]

  variables {
    billing_admin_members = ["billing@example.com"]
  }
}
