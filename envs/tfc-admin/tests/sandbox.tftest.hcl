# Sandbox estate: a second tfc-admin instance runs the committed
# config/sandbox/ files in its own HCP organization. Each estate's workspaces
# trigger only on that estate's config (editing one estate's YAML must not
# queue the other's runs), and auto_apply_on_merge turns on auto-apply plus
# run-trigger auto-apply for every workspace except tfc-admin and
# gcp-guardrails.

mock_provider "tfe" {}

variables {
  tfc_organization = "acme"
  environments = {
    dev = {}
  }
  enable_gcp      = true
  enable_aws      = true
  enable_saas     = true
  saas_workspaces = ["web"]
  # Production layout: the config lookup is off, so the estate is the default
  # config/landing-zone.yaml + config/tfc-workspaces.yaml.
  landing_zone_config_path   = ""
  workspace_variables_file   = null
  manage_tfc_admin_workspace = true
  import_tfc_admin_workspace = false
  security_team_id           = "team-security1"
  # Policy sets are off in most runs; the policy_sets_* runs turn the
  # unguarded-destroy warning back on and expect it.
  enable_unguarded_destroy_warning = false
}

run "production_patterns_exclude_sandbox_config" {
  command = plan

  variables {
    # Not the committed default (a fork's real config/tfc-workspaces.yaml would
    # load into this suite); it does not exist, so only its path is used.
    workspace_variables_file = "../../config/tfc-workspaces.sandbox-test-missing.yaml"
  }

  assert {
    condition = alltrue([
      for ws in output.workspace_names : (
        contains(module.workspace[ws].trigger_patterns, "config/landing-zone.yaml") &&
        contains(module.workspace[ws].trigger_patterns, "config/tfc-workspaces.sandbox-test-missing.yaml") &&
        !anytrue([for p in module.workspace[ws].trigger_patterns : startswith(p, "config/sandbox") || p == "config/**"])
      )
    ])
    error_message = "every production workspace must trigger on its landing-zone config and workspace_variables_file, and never on config/sandbox/**."
  }

  # Existing patterns stay: the root's own dir and the modules it composes.
  assert {
    condition     = toset(module.workspace["gcp-projects"].trigger_patterns) == toset(["envs/gcp/projects/**", "modules/gcp/project/**", "modules/gcp/stages/projects/**", "config/landing-zone.yaml", "config/tfc-workspaces.sandbox-test-missing.yaml"])
    error_message = "the estate config patterns are added to the working-directory and composed-module patterns."
  }

  assert {
    condition     = output.estate_config_trigger_patterns == tolist(["config/landing-zone.yaml", "config/tfc-workspaces.sandbox-test-missing.yaml"])
    error_message = "the production estate's config patterns are its landing-zone file and its workspace_variables_file."
  }
}

# The default (null) path resolves to the same production layout.
run "default_path_is_production_estate" {
  command = plan

  variables {
    landing_zone_config_path = null
    # Pin the values a fork's real config/landing-zone.yaml could otherwise set.
    vcs_repo = null
  }

  assert {
    condition     = output.estate_config_trigger_patterns == tolist(["config/landing-zone.yaml"])
    error_message = "landing_zone_config_path = null is the production estate (workspace_variables_file = null adds no pattern)."
  }
}

run "sandbox_patterns_only_sandbox_config" {
  command = plan

  variables {
    landing_zone_config_path = "../../config/sandbox/landing-zone.yaml"
    workspace_variables_file = "../../config/sandbox/tfc-workspaces.yaml"
    enable_saas              = false
    saas_workspaces          = []
  }

  assert {
    condition     = output.estate_config_trigger_patterns == tolist(["config/sandbox/**"])
    error_message = "the sandbox estate's config pattern is config/sandbox/**."
  }

  assert {
    condition = alltrue([
      for ws in output.workspace_names : (
        contains(module.workspace[ws].trigger_patterns, "config/sandbox/**") &&
        !contains(module.workspace[ws].trigger_patterns, "config/landing-zone.yaml") &&
        !contains(module.workspace[ws].trigger_patterns, "config/tfc-workspaces.yaml")
      )
    ])
    error_message = "sandbox workspaces must trigger on config/sandbox/** and never on the production config files."
  }

  assert {
    condition     = toset(module.workspace["aws-identity"].trigger_patterns) == toset(["envs/aws/identity/**", "modules/aws/iam/iam-identity-center/**", "config/sandbox/**"])
    error_message = "the sandbox pattern is added to the working-directory and composed-module patterns."
  }
}

# The committed sandbox files plan on their own: GCP dev + AWS workload_dev, and
# every workspace is pointed at the sandbox landing-zone config.
run "sandbox_config_files_plan" {
  command = plan

  variables {
    tfc_organization         = null
    environments             = null
    enable_gcp               = null
    enable_aws               = null
    enable_saas              = null
    saas_workspaces          = null
    landing_zone_config_path = "../../config/sandbox/landing-zone.yaml"
    workspace_variables_file = "../../config/sandbox/tfc-workspaces.yaml"
  }

  assert {
    condition = output.workspace_names == sort([
      "gcp-bootstrap", "gcp-organization", "gcp-projects", "gcp-network-hub", "gcp-guardrails", "gcp-workload-dev",
      "aws-organization", "aws-security", "aws-network", "aws-identity", "aws-shared-services", "aws-backup", "aws-workload-dev",
      "tfc-admin",
    ])
    error_message = "the sandbox estate declares the GCP control plane + gcp-workload-dev, the AWS control plane + aws-workload-dev, and tfc-admin."
  }

  assert {
    condition     = output.workspace_variables_file_loaded
    error_message = "config/sandbox/tfc-workspaces.yaml must load."
  }

  assert {
    condition = alltrue([
      for ws in output.workspace_names :
      module.workspace[ws].variable_values["landing_zone_config_path"] == "../../../config/sandbox/landing-zone.yaml"
      if ws != "tfc-admin"
    ])
    error_message = "every sandbox cloud workspace must read config/sandbox/landing-zone.yaml."
  }

  assert {
    condition     = output.workspace_execution_modes["gcp-bootstrap"] == "local"
    error_message = "sandbox phase 0 is the same as production: gcp-bootstrap runs locally first."
  }
}

run "auto_apply_on_merge_excludes_tfc_admin_and_guardrails" {
  command = plan

  variables {
    auto_apply_on_merge = true
  }

  assert {
    condition     = toset(output.never_auto_apply_workspaces) == toset(["gcp-guardrails", "tfc-admin"])
    error_message = "tfc-admin and gcp-guardrails are the never-auto-apply workspaces."
  }

  assert {
    condition = alltrue([
      for ws in output.workspace_names :
      module.workspace[ws].auto_apply == !contains(output.never_auto_apply_workspaces, ws) &&
      module.workspace[ws].auto_apply_run_trigger == !contains(output.never_auto_apply_workspaces, ws)
    ])
    error_message = "auto_apply_on_merge must set auto_apply and auto_apply_run_trigger on every workspace except tfc-admin and gcp-guardrails."
  }

  assert {
    condition     = module.workspace["tfc-admin"].auto_apply == false && module.workspace["gcp-guardrails"].auto_apply == false && module.workspace["gcp-guardrails"].auto_apply_run_trigger == false
    error_message = "tfc-admin and gcp-guardrails always need a human apply confirmation."
  }

  # Path-filtered VCS triggers stay on.
  assert {
    condition     = alltrue([for ws in output.workspace_names : length(module.workspace[ws].trigger_patterns) > 0])
    error_message = "auto_apply_on_merge keeps the path-filtered VCS triggers."
  }
}

run "default_is_manual_apply" {
  command = plan

  assert {
    condition = alltrue([
      for ws in output.workspace_names :
      module.workspace[ws].auto_apply == false && module.workspace[ws].auto_apply_run_trigger == false
    ])
    error_message = "auto_apply_on_merge defaults to false: every workspace keeps manual apply (dev omits is_production, so it is not opted into run-trigger auto-apply)."
  }
}

# A sandbox workspace_variables_file outside the estate directory is still
# watched, as its own pattern.
run "sandbox_workspace_variables_file_outside_dir" {
  command = plan

  variables {
    landing_zone_config_path = "../../config/sandbox/landing-zone.yaml"
    workspace_variables_file = "../../config/sandbox-vars.missing.yaml"
    enable_saas              = false
    saas_workspaces          = []
  }

  assert {
    condition     = output.estate_config_trigger_patterns == tolist(["config/sandbox/**", "config/sandbox-vars.missing.yaml"])
    error_message = "a workspace_variables_file outside the estate dir gets its own trigger pattern."
  }
}

# A relative config path that leaves the repository cannot become a trigger
# glob: the plan fails instead.
run "config_path_outside_repo_rejected" {
  command = plan

  variables {
    landing_zone_config_path = "../../../outside/landing-zone.yaml"
  }

  expect_failures = [var.landing_zone_config_path]
}

run "config_path_above_root_rejected" {
  command = plan

  variables {
    landing_zone_config_path = "../landing-zone.yaml"
  }

  expect_failures = [var.landing_zone_config_path]
}

run "workspace_variables_file_outside_repo_rejected" {
  command = plan

  variables {
    workspace_variables_file = "../../../tfc-workspaces.yaml"
  }

  expect_failures = [var.workspace_variables_file]
}
