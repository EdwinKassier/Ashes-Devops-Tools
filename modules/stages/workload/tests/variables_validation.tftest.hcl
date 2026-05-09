# Variable validation tests for the workload module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}
mock_provider "google-beta" {}
mock_provider "random" {}

variables {
  project_name              = "mock-workload"
  org_id                    = "123456789"
  folder_id                 = "987654321"
  billing_account           = "ABCDEF-123456-789012"
  project_admin_group_email = "team@example.com"
  # enable_shared_vpc_attachment defaults to true; provide a stub subnet so validation passes.
  shared_vpc_subnets = {
    primary = {
      region      = "us-central1"
      subnet_name = "mock-private-subnet"
    }
  }
}

# ── project_admin_roles ────────────────────────────────────────────────────────
# Full coverage (primitives, cross-boundary privileged, edge cases) lives in
# tests/iam_validation.tftest.hcl. Only smoke-test the happy path here to avoid
# duplication and keep this file focused on cross-variable validation rules.

run "accepts_predefined_least_privilege_roles" {
  command = plan

  variables {
    project_admin_roles = [
      "roles/compute.admin",
      "roles/storage.admin",
    ]
  }
}

run "accepts_empty_roles_list" {
  command = plan

  variables {
    project_admin_roles = []
  }
}

# ── org_id ─────────────────────────────────────────────────────────────────────

run "rejects_org_id_with_prefix" {
  command         = plan
  expect_failures = [var.org_id]
  variables {
    org_id = "organizations/123456789"
  }
}

# ── folder_id ──────────────────────────────────────────────────────────────────

run "rejects_folder_id_with_prefix" {
  command         = plan
  expect_failures = [var.folder_id]
  variables {
    folder_id = "folders/987654321"
  }
}

# ── billing_account ────────────────────────────────────────────────────────────

run "rejects_lowercase_billing_account" {
  command         = plan
  expect_failures = [var.billing_account]
  variables {
    billing_account = "abcdef-123456-789012"
  }
}

run "rejects_billing_account_wrong_format" {
  command         = plan
  expect_failures = [var.billing_account]
  variables {
    billing_account = "ABCDEF123456789012"
  }
}

# ── project_admin_group_email ──────────────────────────────────────────────────

run "rejects_invalid_admin_group_email" {
  command         = plan
  expect_failures = [var.project_admin_group_email]
  variables {
    project_admin_group_email = "not-an-email"
  }
}

# ── shared_vpc_subnets (guard: must be non-empty when enable_shared_vpc_attachment = true) ──

run "accepts_shared_vpc_with_subnets" {
  command = plan
  variables {
    enable_shared_vpc_attachment = true
    shared_vpc_subnets = {
      primary = {
        region      = "us-central1"
        subnet_name = "private-subnet"
      }
    }
  }
}

run "accepts_no_shared_vpc_without_subnets" {
  command = plan
  variables {
    enable_shared_vpc_attachment = false
    shared_vpc_subnets           = {}
  }
}

run "rejects_shared_vpc_with_no_subnets" {
  command         = plan
  expect_failures = [var.shared_vpc_subnets]
  variables {
    enable_shared_vpc_attachment = true
    shared_vpc_subnets           = {}
  }
}
