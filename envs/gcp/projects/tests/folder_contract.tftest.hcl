# The gcp-organization contract carries google_folder's real shape: id is the
# bare folder number (folder_id) and name is folders/<number>. A project parent
# needs folders/<number>, so the projects stage must read name. Here the real
# projects stage plans (no override_module) from a config-file contract whose
# dev folder has only the bare number and whose prod folder uses the
# folders/<number> id form; both must yield a valid project parent.

mock_provider "google" {}
mock_provider "google-beta" {}
mock_provider "random" {}

variables {
  landing_zone_config_path = "tests/fixtures/landing-zone-folder-contract.yaml"
}

run "project_parent_from_numeric_folder_id" {
  command = plan

  assert {
    condition     = local.org.folders["dev"].id == "111" && local.org.folders["dev"].name == "folders/111"
    error_message = "A config contract folder with a bare id and no name must normalise to id 111, name folders/111"
  }

  assert {
    condition     = local.org.folders["prod"].id == "222" && local.org.folders["prod"].name == "folders/222"
    error_message = "A config contract folder id in the folders/<number> form must normalise to the bare number"
  }

  assert {
    condition = (
      module.projects.projects["dev-host"].parent == "folders/111" &&
      module.projects.projects["prod-host"].parent == "folders/222" &&
      module.projects.projects["shared-hub"].parent == "folders/100"
    )
    error_message = "Each host project must be created under folders/<number>, whichever id form the contract carried"
  }

  assert {
    condition     = output.environment_config["dev"].folder_id == "111" && output.environment_config["prod"].folder_id == "222"
    error_message = "environment_config.folder_id must be the bare folder number"
  }
}
