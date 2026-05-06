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
}

# ── project_admin_roles ────────────────────────────────────────────────────────

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

run "rejects_owner_basic_role" {
  command = plan

  expect_failures = [var.project_admin_roles]

  variables {
    project_admin_roles = ["roles/owner"]
  }
}

run "rejects_editor_basic_role" {
  command = plan

  expect_failures = [var.project_admin_roles]

  variables {
    project_admin_roles = ["roles/editor"]
  }
}

run "rejects_viewer_basic_role" {
  command = plan

  expect_failures = [var.project_admin_roles]

  variables {
    project_admin_roles = ["roles/viewer"]
  }
}

run "rejects_list_containing_basic_role_alongside_predefined" {
  command = plan

  expect_failures = [var.project_admin_roles]

  variables {
    project_admin_roles = [
      "roles/compute.admin",
      "roles/owner",
    ]
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
