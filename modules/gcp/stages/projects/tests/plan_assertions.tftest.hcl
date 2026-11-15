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
    dev = { id = "111111111", name = "folders/111111111", display_name = "Development" }
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
    error_message = "the project must be created under its environment folder's resource name (var.folders[ou].name)"
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

# Per-project API additions (e.g. networkconnectivity.googleapis.com on the hub
# and host projects for NCC) land only on the named project, on top of the
# baseline; the default {} keeps the baseline everywhere.
run "additional_project_services_reach_only_the_named_project" {
  command = plan

  variables {
    environments = {
      dev = {
        display_name = "Development"
        description  = "Development environment"
        projects = {
          host  = { name = "host", labels = {} }
          tools = { name = "tools", labels = {} }
        }
      }
    }
    additional_project_services = {
      "dev-host"   = ["networkconnectivity.googleapis.com"]
      "no-such-pj" = ["networkconnectivity.googleapis.com"]
    }
  }

  assert {
    condition     = contains(module.project["dev-host"].services, "networkconnectivity.googleapis.com") && length(module.project["dev-host"].services) == 7
    error_message = "additional_project_services must add the API to the named project on top of project_services."
  }

  assert {
    condition     = !contains(module.project["dev-tools"].services, "networkconnectivity.googleapis.com") && length(module.project["dev-tools"].services) == 6
    error_message = "Other projects must keep only project_services."
  }
}

# Per-project tag bindings (gcp-projects binds data-classification to each
# environment host project) and the owner label (org.owner in the roots).
run "project_tag_bindings_and_owner_label" {
  command = plan

  variables {
    owner = "data-team"
    environments = {
      dev = {
        display_name = "Development"
        description  = "Development environment"
        projects = {
          host = {
            name         = "host"
            labels       = {}
            tag_bindings = { data_classification = "tagValues/900000000004" }
          }
          tools = { name = "tools", labels = {} }
        }
      }
    }
  }

  assert {
    condition = (
      module.project["dev-host"].tag_bindings == { data_classification = "tagValues/900000000004" } &&
      length(module.project["dev-tools"].tag_bindings) == 0 &&
      module.project["dev-host"].labels["owner"] == "data-team"
    )
    error_message = "a project's tag_bindings must reach the project primitive (only that project), and var.owner must set the owner label."
  }
}

run "project_parent_is_folder_name_not_numeric_id" {
  # The gcp-organization contract carries the real google_folder shape: id is
  # the bare number (folder_id), name is folders/<number>. The project parent
  # needs folders/<number>, so it must come from name, never from id.
  command = plan

  variables {
    folders = {
      dev = { id = "222222222", name = "folders/222222222", display_name = "Development" }
    }
  }

  assert {
    condition     = module.project["dev-host"].parent == "folders/222222222"
    error_message = "A numeric folder id must still yield the project parent folders/<number>"
  }
}
