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

  assert {
    condition     = output.variable_values == { tfc_organization = "acme", TFC_AWS_PROVIDER_AUTH = "true" }
    error_message = "variable_values must expose the non-sensitive values."
  }
}

run "variable_values_omit_sensitive" {
  command = plan

  variables {
    variables = {
      region = { value = "eu-west-2", category = "terraform" }
      token  = { value = "s3cr3t", category = "env", sensitive = true }
    }
  }

  assert {
    condition     = !contains(keys(output.variable_values), "token") && output.variable_values["region"] == "eu-west-2"
    error_message = "sensitive variables must not appear in variable_values."
  }
}

# Opt-in run notifications (audit M-ops): default off, and a configured one wires
# through to a tfe_notification_configuration with the failed-run triggers.
run "notifications_default_off" {
  command = plan

  assert {
    condition     = length(tfe_notification_configuration.this) == 0
    error_message = "with no notifications declared, no notification configuration is created."
  }
}

run "notifications_wire_through" {
  command = plan

  variables {
    notifications = {
      ci-webhook = {
        destination_type = "generic"
        url              = "https://example.com/hooks/ci"
      }
    }
  }

  assert {
    condition     = length(tfe_notification_configuration.this) == 1
    error_message = "one notification configuration must be created per entry."
  }

  assert {
    condition     = contains(tfe_notification_configuration.this["ci-webhook"].triggers, "run:errored")
    error_message = "the default triggers must include a failed run (run:errored)."
  }
}

# Settings: remote state is NOT global by default and only the listed consumers
# may read it; execution mode is set on tfe_workspace_settings.
run "remote_state_explicit_consumers" {
  command = plan

  variables {
    remote_state_consumer_ids = ["ws-consumer1", "ws-consumer2"]
  }

  assert {
    condition     = tfe_workspace_settings.this[0].global_remote_state == false
    error_message = "global_remote_state must default to false."
  }

  assert {
    condition     = toset(tfe_workspace_settings.this[0].remote_state_consumer_ids) == toset(["ws-consumer1", "ws-consumer2"])
    error_message = "remote_state_consumer_ids must be wired to the settings resource."
  }

  assert {
    condition     = tfe_workspace_settings.this[0].execution_mode == "remote"
    error_message = "execution_mode must be set on tfe_workspace_settings."
  }
}

run "settings_can_be_caller_managed" {
  command = plan

  variables {
    manage_settings = false
  }

  assert {
    condition     = length(tfe_workspace_settings.this) == 0
    error_message = "manage_settings = false must not create tfe_workspace_settings."
  }
}

# Triggers, speculative plans, health assessments and variable-set attachment.
run "control_plane_hardening_wires_through" {
  command = plan

  variables {
    trigger_patterns    = ["envs/gcp/organization/**", "modules/gcp/**"]
    speculative_enabled = false
    allow_destroy_plan  = false
    variable_set_ids    = { common = "varset-abc123" }
  }

  assert {
    condition     = tfe_workspace.this.trigger_patterns == tolist(["envs/gcp/organization/**", "modules/gcp/**"])
    error_message = "trigger_patterns must be passed through to the workspace."
  }

  assert {
    condition     = tfe_workspace.this.speculative_enabled == false && tfe_workspace.this.allow_destroy_plan == false
    error_message = "speculative_enabled / allow_destroy_plan must be passed through."
  }

  assert {
    condition     = tfe_workspace.this.assessments_enabled == true
    error_message = "health assessments must default on."
  }

  assert {
    condition     = tfe_workspace_variable_set.this["common"].variable_set_id == "varset-abc123"
    error_message = "each variable_set_ids entry must attach the set to the workspace."
  }
}

run "speculative_plans_default_on" {
  command = plan

  assert {
    condition     = tfe_workspace.this.speculative_enabled == true && tfe_workspace.this.trigger_patterns == null
    error_message = "a plain workspace keeps speculative plans and the working-directory trigger default."
  }
}
