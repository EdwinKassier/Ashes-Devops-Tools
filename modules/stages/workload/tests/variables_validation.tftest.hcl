# Variable validation tests for the workload module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}
mock_provider "google-beta" {}
mock_provider "random" {}

variables {
  project_name              = "mock-workload"
  org_id                    = "123456789"
  folder_id                 = "folders/987654321"
  billing_account           = "012345-6789AB-CDEF01"
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
