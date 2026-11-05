# Regression test for the computed project_id naming convention.
#
# module.project[*].project_id (the shared project primitive) is built as
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
    condition = length(module.project) > 0 && alltrue([
      for p in module.project : p.project_id == "my-org-dev-host-abcd1234"
    ])
    error_message = "project_id must be computed as <project_prefix>-<environment_key>-<project.name>-<suffix>"
  }

  assert {
    condition     = module.project["dev-host"].parent == "folders/111111111"
    error_message = "the project must be wired to the folder_id of its owning environment (var.folders[ou].id)"
  }
}

run "short_project_names_get_env_prefixed_display_name" {
  command = plan

  variables {
    environments = {
      dev = {
        display_name = "Development"
        description  = "Development environment"
        projects = {
          hub = { name = "hub", labels = {} }
        }
      }
    }
  }

  assert {
    condition     = module.project["dev-hub"].name == "dev-hub" && module.project["dev-hub"].project_id == "my-org-dev-hub-abcd1234"
    error_message = "A <4-char project name must get an env-prefixed display name (provider requires 4-30) without changing project_id."
  }
}

run "projects_get_labels_services_and_metrics_scope" {
  command = plan

  assert {
    condition = (
      module.project["dev-host"].labels["environment"] == "dev" &&
      module.project["dev-host"].labels["managed-by"] == "terraform" &&
      module.project["dev-host"].labels["organization"] == "example"
    )
    error_message = "Stage labels (managed-by / organization / environment) must reach the project primitive."
  }

  assert {
    condition     = contains(module.project["dev-host"].services, "compute.googleapis.com") && length(module.project["dev-host"].services) == 6
    error_message = "var.project_services must be enabled on every project through the primitive."
  }

  assert {
    condition     = google_monitoring_monitored_project.projects["dev-host"].name == "locations/global/metricsScopes/mock-admin-project/projects/my-org-dev-host-abcd1234"
    error_message = "Every project must be added to the admin project's metrics scope."
  }

  assert {
    condition     = output.project_ids["dev-host"] == "my-org-dev-host-abcd1234" && output.projects["dev-host"].parent == "folders/111111111"
    error_message = "project_ids / projects outputs must be built from the primitive."
  }
}

run "organization_label_is_sanitised" {
  command = plan

  variables {
    organization_name = "My Organization"
  }

  assert {
    condition     = module.project["dev-host"].labels["organization"] == "my-organization"
    error_message = "organization_name must be normalised to a valid GCP label value."
  }
}
