# Plan assertions for the iam/role module: verify the custom role is planned at the
# requested level with the caller-supplied id/permissions.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  role_id     = "myCustomRole"
  title       = "My Custom Role"
  permissions = ["storage.objects.get"]
  project_id  = "mock-project"
}

run "project_custom_role_planned" {
  command = plan

  variables {
    level = "project"
  }

  assert {
    condition     = length(google_project_iam_custom_role.project_role) == 1
    error_message = "A project custom role must be planned when level = project."
  }

  assert {
    condition     = google_project_iam_custom_role.project_role[0].role_id == var.role_id
    error_message = "Custom role id must be the caller-supplied role_id."
  }

  assert {
    condition     = length(google_organization_iam_custom_role.org_role) == 0
    error_message = "No organization custom role must be planned when level = project."
  }
}

run "organization_custom_role_planned" {
  command = plan

  variables {
    level  = "organization"
    org_id = "123456789"
  }

  assert {
    condition     = length(google_organization_iam_custom_role.org_role) == 1
    error_message = "An organization custom role must be planned when level = organization."
  }
}
