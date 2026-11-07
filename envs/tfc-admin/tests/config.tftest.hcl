# Single-source configuration: with tfc_organization / environments / enable_* /
# saas_workspaces / project_name_prefix / vcs_repo unset, tfc-admin derives the
# whole workspace layer from the landing-zone config file (a fixture here,
# config/landing-zone.yaml in a real estate). Explicit variables still win.

mock_provider "tfe" {}

variables {
  landing_zone_config_path = "tests/fixtures/landing-zone.yaml"
  workspace_variables_file = null
  # The fixture sets vcs_repo, so tfc-admin is self-managed (the default).
  # Mock providers cannot import; the import block runs in the adopting apply.
  import_tfc_admin_workspace = false
  # gcp-guardrails is security-team only; without a team a check warns.
  security_team_id = "team-security1"
  # Policy sets are off in most runs; the policy_sets_* runs turn the
  # unguarded-destroy warning back on and expect it.
  enable_unguarded_destroy_warning = false
}

run "workspaces_derived_from_config" {
  command = plan

  # 5 GCP control plane (incl. gcp-guardrails) + gcp-workload-{dev,prod} + 6 AWS
  # control plane + aws-workload-{dev,staging} + saas-{web,admin} + tfc-admin
  # (self-managed) = 18.
  assert {
    condition     = length(output.workspace_names) == 18
    error_message = "the workspace set must come from gcp/aws/saas .enabled, gcp.environments, aws.workload_environments and saas.workspaces."
  }

  # Each cloud uses its own environment list: no aws-workload-prod, no
  # gcp-workload-staging.
  assert {
    condition     = alltrue([for w in ["gcp-workload-dev", "gcp-workload-prod", "aws-workload-dev", "aws-workload-staging", "saas-web", "saas-admin"] : contains(output.workspace_names, w)]) && !contains(output.workspace_names, "aws-workload-prod") && !contains(output.workspace_names, "gcp-workload-staging")
    error_message = "gcp-workload-<env> must follow gcp.environments and aws-workload-<env> aws.workload_environments."
  }

  assert {
    condition     = local.tfc_organization == "cfg-tfc" && tfe_variable.common["tfc_organization"].value == "cfg-tfc" && tfe_project.this["gcp"].organization == "cfg-tfc"
    error_message = "tfc_organization must fall back to org.tfc.organization."
  }
}

# Speculative plans follow is_production from gcp.environments /
# aws.workload_environments (aws staging is flagged production in the fixture).
run "production_from_config" {
  command = plan

  assert {
    condition     = module.workspace["gcp-workload-prod"].speculative_enabled == false && module.workspace["aws-workload-staging"].speculative_enabled == false
    error_message = "workloads whose environment is_production must not run speculative plans."
  }

  assert {
    condition     = module.workspace["gcp-workload-dev"].speculative_enabled == true && module.workspace["aws-workload-dev"].speculative_enabled == true
    error_message = "non-production workloads keep speculative plans."
  }
}

run "workload_account_key_from_config" {
  command = plan

  assert {
    condition     = module.workspace["aws-workload-staging"].variable_values["workload_account_key"] == "workload_staging" && module.workspace["aws-workload-staging"].variable_values["environment"] == "staging"
    error_message = "aws-workload-<env> must get workload_account_key from aws.workload_environments[<env>].account_key."
  }
}

# Project names: <project_name_prefix><cloud>, with an explicit
# org.tfc.aws_project winning (the same key aws-organization's tfc_project reads).
run "project_names_from_config" {
  command = plan

  assert {
    condition     = tfe_project.this["gcp"].name == "lz-gcp" && tfe_project.this["saas"].name == "lz-saas" && tfe_project.this["aws"].name == "aws-landing-zone"
    error_message = "project names must come from org.tfc.project_name_prefix / org.tfc.<cloud>_project."
  }

  assert {
    condition     = tfe_variable_set.common.name == "lz-common"
    error_message = "the variable-set name must use the config project_name_prefix."
  }
}

run "vcs_repo_and_pinned_opa_from_config" {
  command = plan

  variables {
    enable_policy_sets = true
  }

  assert {
    condition     = tfe_policy_set.opa[0].vcs_repo[0].identifier == "cfg/landing-zone" && tfe_policy_set.opa[0].vcs_repo[0].branch == "main" && tfe_policy_set.opa[0].policy_tool_version == "1.22.2"
    error_message = "vcs_repo must fall back to org.tfc.vcs_repo (branch default main) and opa_version must be pinned by default."
  }
}

run "explicit_variables_win_over_config" {
  command = plan

  variables {
    tfc_organization    = "acme"
    enable_aws          = false
    enable_saas         = false
    project_name_prefix = "x-"
    environments        = { qa = {} }
    enable_policy_sets  = true
    vcs_repo            = { identifier = "acme/landing-zone", oauth_token_id = "ot-abc123" }
  }

  assert {
    condition     = tfe_policy_set.opa[0].vcs_repo[0].identifier == "acme/landing-zone"
    error_message = "an explicit vcs_repo must override org.tfc.vcs_repo."
  }

  assert {
    condition     = toset(output.workspace_names) == toset(["gcp-bootstrap", "gcp-organization", "gcp-projects", "gcp-network-hub", "gcp-guardrails", "gcp-workload-qa", "tfc-admin"]) && local.tfc_organization == "acme"
    error_message = "explicit enable_* / environments / tfc_organization must override the config file."
  }

  # The config's explicit org.tfc.gcp_project is unset, so the variable prefix applies.
  assert {
    condition     = tfe_project.this["gcp"].name == "x-gcp"
    error_message = "an explicit project_name_prefix must override org.tfc.project_name_prefix."
  }
}

run "missing_organization_fails" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/does-not-exist.yaml"
    enable_gcp               = true
  }

  expect_failures = [var.tfc_organization]
}

run "untouched_placeholder_rejected" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-placeholder.yaml"
  }

  expect_failures = [var.tfc_organization]
}

run "shipped_example_is_rejected" {
  command = plan

  variables {
    landing_zone_config_path = "../../config/landing-zone.example.yaml"
  }

  # Placeholder TFC org, and every cloud disabled until the adopter opts in.
  expect_failures = [var.tfc_organization, var.enable_gcp]
}

# enable_policy_sets = null: the fixture sets org.tfc.vcs_repo and
# org.tfc.plan = standard, so both policy sets turn on by themselves.
run "policy_sets_on_with_vcs_and_paid_plan" {
  command = plan

  assert {
    condition     = length(tfe_policy_set.opa) == 1 && length(tfe_policy_set.destructive) == 1
    error_message = "a vcs_repo plus a plan with VCS policy sets must turn both policy sets on."
  }

  assert {
    condition     = tfe_policy_set.destructive[0].overridable == true && tfe_policy_set.opa[0].overridable == false
    error_message = "only the destructive-change guard is overridable."
  }
}

run "policy_sets_off_on_free_plan" {
  command = plan

  variables {
    tfc_plan                         = "free"
    enable_unguarded_destroy_warning = true
  }

  assert {
    condition     = length(tfe_policy_set.opa) == 0 && length(tfe_policy_set.destructive) == 0
    error_message = "the free plan does not get the policy sets by default."
  }

  expect_failures = [check.destructive_changes_guarded]
}

run "explicit_enable_policy_sets_false_wins" {
  command = plan

  variables {
    enable_policy_sets               = false
    enable_unguarded_destroy_warning = true
  }

  assert {
    condition     = length(tfe_policy_set.opa) == 0 && length(tfe_policy_set.destructive) == 0
    error_message = "an explicit enable_policy_sets = false must override the derived default."
  }

  expect_failures = [check.destructive_changes_guarded]
}

# notifications.hcp_email_user_ids becomes an email notification (user IDs, not
# addresses) on failed runs and every health-assessment event.
run "hcp_assessment_notifications_use_user_ids" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-notifications.yaml"
  }

  assert {
    condition = (
      local.control_plane_notifications["notify-email"].destination_type == "email" &&
      toset(local.control_plane_notifications["notify-email"].email_user_ids) == toset(["user-aaa", "user-bbb"]) &&
      contains(local.control_plane_notifications["notify-email"].triggers, "assessment:drifted") &&
      contains(local.control_plane_notifications["notify-email"].triggers, "assessment:check_failure") &&
      contains(local.control_plane_notifications["notify-email"].triggers, "assessment:failed") &&
      contains(local.control_plane_notifications["notify-email"].triggers, "run:errored")
    )
    error_message = "hcp_email_user_ids must produce an email notification with run:errored and the three assessment triggers."
  }

  assert {
    condition     = contains(keys(local.workload_notifications), "notify-email")
    error_message = "workload workspaces must receive the assessment email notification too."
  }
}

# Explicitly configured notifications are kept; the section only adds its entry.
run "explicit_notifications_are_kept" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-notifications.yaml"
    control_plane_notifications = {
      ops = { destination_type = "generic", url = "https://hooks.example.com/x" }
    }
  }

  assert {
    condition     = contains(keys(local.control_plane_notifications), "ops") && contains(keys(local.control_plane_notifications), "notify-email")
    error_message = "an explicit notification must be kept alongside the config-derived email entry."
  }
}

run "no_section_is_noop" {
  command = plan

  assert {
    condition     = length(local.control_plane_notifications) == 0 && length(local.workload_notifications) == 0
    error_message = "without a notifications section no notification is created."
  }
}
