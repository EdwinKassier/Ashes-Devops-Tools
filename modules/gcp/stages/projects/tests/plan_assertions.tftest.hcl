# Regression test for the computed project_id naming convention.
#
# google_project.projects.project_id is built as
# "<project_prefix>-<environment_key>-<project.name>-<suffix>" (see main.tf).
# This asserts that computed id actually reaches the plan in the expected
# format and that the project is wired to the correct folder — the existing
# variables_validation.tftest.hcl only proves inputs are accepted/rejected,
# never that the naming/folder-wiring logic is correct.

mock_provider "google" {}

variables {
  project_prefix          = "my-org"
  organization_name       = "example"
  default_billing_account = "ABCDEF-123456-789012"
  admin_project_id        = "mock-admin-project"
  suffix                  = "abcd1234"
  folders = {
    dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" }
  }
  environments = {
    dev = {
      display_name = "Development"
      description  = "Development environment"
      projects = {
        host = {
          name   = "host"
          labels = {}
        }
      }
    }
  }
}

run "project_id_follows_prefix_env_name_suffix_convention" {
  command = plan

  assert {
    # length check first — alltrue([]) is vacuously true (see CONTRIBUTING.md Testing).
    condition = length(google_project.projects) > 0 && alltrue([
      for p in google_project.projects : p.project_id == "my-org-dev-host-abcd1234"
    ])
    error_message = "project_id must be computed as <project_prefix>-<environment_key>-<project.name>-<suffix>"
  }

  assert {
    condition     = google_project.projects["dev-host"].folder_id == "folders/111111111"
    error_message = "the project must be wired to the folder_id of its owning environment (var.folders[ou].id)"
  }
}
