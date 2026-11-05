mock_provider "tfe" {}

variables {
  name              = "gcp-organization"
  organization      = "acme"
  description       = "GCP control plane"
  working_directory = "envs/gcp/organization"
  tag_names         = ["cloud:gcp", "layer:control-plane"]
  variables = {
    tfc_organization      = { value = "acme", category = "terraform" }
    TFC_AWS_PROVIDER_AUTH = { value = "true", category = "env" }
  }
}

run "workspace_configured" {
  command = plan

  assert {
    condition     = tfe_workspace.this.name == "gcp-organization" && tfe_workspace.this.working_directory == "envs/gcp/organization"
    error_message = "workspace must be created with the given name and working directory."
  }

  # Foundational workspaces are manual-apply by default.
  assert {
    condition     = tfe_workspace.this.auto_apply == false
    error_message = "auto_apply must default to false so foundational applies are deliberate."
  }

  # One tfe_variable per entry in the variables map.
  assert {
    condition     = length(tfe_variable.this) == 2
    error_message = "a tfe_variable must be created for each entry in var.variables."
  }

  assert {
    condition     = tfe_variable.this["tfc_organization"].category == "terraform" && tfe_variable.this["TFC_AWS_PROVIDER_AUTH"].category == "env"
    error_message = "variable categories must be wired through (terraform vs env)."
  }
}
