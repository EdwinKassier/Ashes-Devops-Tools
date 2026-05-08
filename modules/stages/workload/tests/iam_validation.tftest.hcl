# These tests use mock_provider so no GCP credentials are required.
# They validate that the project_admin_roles variable correctly rejects
# primitive IAM roles (owner/editor/viewer) and cross-boundary privileged roles
# (organizationAdmin, folderAdmin, securityAdmin, etc.) at plan time.

mock_provider "google" {}
mock_provider "google-beta" {}
mock_provider "random" {}

# Required variables shared across all runs; Shared VPC disabled so no host
# project credentials are needed.
variables {
  project_name                 = "mock-service"
  org_id                       = "123456789"
  folder_id                    = "111111111"
  billing_account              = "000000-000000-000000"
  project_admin_group_email    = "admins@example.com"
  enable_shared_vpc_attachment = false
}

# ── Accept ─────────────────────────────────────────────────────────────────────

run "accepts_predefined_least_privilege_roles" {
  command = plan

  variables {
    project_admin_roles = [
      "roles/storage.admin",
      "roles/bigquery.dataEditor",
      "roles/logging.viewer",
    ]
  }
}

run "accepts_custom_role" {
  command = plan

  variables {
    project_admin_roles = ["projects/my-project/roles/customRole"]
  }
}

run "accepts_empty_roles_list" {
  command = plan

  variables {
    project_admin_roles = []
  }
}

# ── Reject primitive roles ─────────────────────────────────────────────────────

run "rejects_owner_role" {
  command = plan

  expect_failures = [var.project_admin_roles]

  variables {
    project_admin_roles = ["roles/owner"]
  }
}

run "rejects_editor_role" {
  command = plan

  expect_failures = [var.project_admin_roles]

  variables {
    project_admin_roles = ["roles/editor"]
  }
}

run "rejects_viewer_role" {
  command = plan

  expect_failures = [var.project_admin_roles]

  variables {
    project_admin_roles = ["roles/viewer"]
  }
}

run "rejects_mixed_list_containing_owner" {
  # Validation must reject the entire list even when only one entry is a primitive role
  command = plan

  expect_failures = [var.project_admin_roles]

  variables {
    project_admin_roles = ["roles/storage.admin", "roles/owner"]
  }
}

# ── Reject cross-boundary privileged roles ────────────────────────────────────
# These roles span beyond the project boundary and must never be granted at
# project level via an authoritative google_project_iam_binding.

run "rejects_organization_admin" {
  command = plan

  expect_failures = [var.project_admin_roles]

  variables {
    project_admin_roles = ["roles/resourcemanager.organizationAdmin"]
  }
}

run "rejects_folder_admin" {
  command = plan

  expect_failures = [var.project_admin_roles]

  variables {
    project_admin_roles = ["roles/resourcemanager.folderAdmin"]
  }
}

run "rejects_iam_security_admin" {
  command = plan

  expect_failures = [var.project_admin_roles]

  variables {
    project_admin_roles = ["roles/iam.securityAdmin"]
  }
}

run "rejects_organization_role_admin" {
  command = plan

  expect_failures = [var.project_admin_roles]

  variables {
    project_admin_roles = ["roles/iam.organizationRoleAdmin"]
  }
}

run "rejects_billing_admin" {
  command = plan

  expect_failures = [var.project_admin_roles]

  variables {
    project_admin_roles = ["roles/billing.admin"]
  }
}
