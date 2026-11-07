# Contract test for the tfc-admin root: the declared workspace set matches the
# cloud roots (enable_gcp / enable_aws / enable_saas toggles + environments map),
# and every workspace carries the hardened TFC settings: trigger patterns over
# the module domains it consumes, no speculative plans on the control plane,
# explicit remote-state consumers, and dynamic-credential env vars only when
# their inputs are supplied.

mock_provider "tfe" {}

variables {
  tfc_organization = "acme"
  environments = {
    dev  = {}
    prod = {}
  }
  enable_gcp      = true
  enable_aws      = true
  enable_saas     = true
  saas_workspaces = ["web"]
  # Keep the suite independent of any committed config/tfc-workspaces.yaml
  # and config/landing-zone.yaml.
  landing_zone_config_path = ""
  workspace_variables_file = null
  # Mock providers cannot import, so the suite runs with an unmanaged
  # tfc-admin workspace; self_management_* runs cover the managed default.
  manage_tfc_admin_workspace = false
  # gcp-guardrails is security-team only; without a team a check warns
  # (guardrails_project_without_security_team_warns).
  security_team_id = "team-security1"
  # Policy sets are off in most runs; the policy_sets_* runs turn the
  # unguarded-destroy warning back on and expect it.
  enable_unguarded_destroy_warning = false
}

run "declares_every_workspace" {
  command = plan

  # 5 GCP control plane (incl. gcp-guardrails) + 2 gcp-workload + 6 AWS control
  # plane + 2 aws-workload + 1 saas = 16.
  assert {
    condition     = length(output.workspace_names) == 16
    error_message = "tfc-admin must declare a workspace for each root, each per-env workload, and each saas entry."
  }

  assert {
    condition = alltrue([
      for k in ["gcp-bootstrap", "gcp-organization", "gcp-projects", "gcp-network-hub", "gcp-guardrails",
      "gcp-workload-dev", "gcp-workload-prod", "aws-security", "aws-workload-prod", "saas-web"] :
      contains(output.workspace_names, k)
    ])
    error_message = "control-plane, per-env workload, and saas workspaces must all be declared."
  }

  # One project per cloud in use, plus the security-only guardrails project; no
  # platform project unless tfc-admin is self-managed.
  assert {
    condition     = toset(keys(tfe_project.this)) == toset(["gcp", "aws", "saas", "guardrails"])
    error_message = "one TFC project per enabled cloud must be created."
  }
}

run "gcp_only" {
  command = plan

  variables {
    enable_aws      = false
    enable_saas     = false
    saas_workspaces = []
  }

  # 5 GCP control plane (incl. gcp-guardrails) + 2 gcp-workload = 7; no AWS
  # workspaces.
  assert {
    condition     = length(output.workspace_names) == 7 && !contains(output.workspace_names, "aws-organization")
    error_message = "with enable_aws=false and no saas, only the GCP workspaces are declared."
  }
}

# An AWS-only adopter opts out of GCP and gets no dead gcp-* workspaces.
run "aws_only_has_no_gcp_workspaces" {
  command = plan

  variables {
    enable_gcp  = false
    enable_saas = false
  }

  assert {
    condition     = length(output.workspace_names) == 8 && length([for n in output.workspace_names : n if startswith(n, "gcp-")]) == 0
    error_message = "enable_gcp = false must declare no gcp-* workspaces (6 AWS control plane + 2 aws-workload = 8)."
  }
}

run "saas_only" {
  command = plan

  variables {
    enable_gcp = false
    enable_aws = false
  }

  assert {
    condition     = output.workspace_names == tolist(["saas-web"])
    error_message = "a SaaS-only estate declares only the saas-<name> workspaces."
  }
}

# Module-only PRs must trigger plans: each workspace watches its own dir, the
# module domains its root consumes, and its estate's config files
# (sandbox.tftest.hcl covers the per-estate split).
run "trigger_patterns_cover_module_domains" {
  command = plan

  assert {
    condition     = toset(module.workspace["gcp-organization"].trigger_patterns) == toset(["envs/gcp/organization/**", "modules/gcp/**", "config/landing-zone.yaml"])
    error_message = "GCP roots must trigger on their dir, modules/gcp/** and the estate config."
  }

  assert {
    condition     = toset(module.workspace["aws-workload-dev"].trigger_patterns) == toset(["envs/aws/workload/**", "modules/aws/**", "config/landing-zone.yaml"])
    error_message = "AWS roots must trigger on their dir, modules/aws/** and the estate config."
  }

  assert {
    condition     = toset(module.workspace["saas-web"].trigger_patterns) == toset(["envs/saas/**", "modules/saas/**", "modules/supabase/**", "modules/vercel/**", "config/landing-zone.yaml"])
    error_message = "the saas root must trigger on envs/saas and the saas/supabase/vercel module domains."
  }
}

# No privileged speculative plan for a PR on the control plane.
run "speculative_plans_off_for_control_plane" {
  command = plan

  assert {
    condition = alltrue([
      for k in ["gcp-bootstrap", "gcp-organization", "gcp-projects", "gcp-network-hub", "aws-organization", "aws-security", "aws-network", "aws-backup", "aws-identity"] :
      module.workspace[k].speculative_enabled == false
    ])
    error_message = "control-plane workspaces must have speculative_enabled = false."
  }

  assert {
    condition     = module.workspace["gcp-workload-dev"].speculative_enabled == true && module.workspace["aws-workload-dev"].speculative_enabled == true
    error_message = "non-production GCP/AWS workload workspaces keep speculative PR plans."
  }

  # SaaS providers use static account-wide tokens with no plan identity.
  assert {
    condition     = module.workspace["saas-web"].speculative_enabled == false
    error_message = "saas-<name> workspaces must not run speculative PR plans (account-wide static tokens)."
  }

  # A PR must not get a plan with the production plan identity.
  assert {
    condition     = module.workspace["gcp-workload-prod"].speculative_enabled == false && module.workspace["aws-workload-prod"].speculative_enabled == false
    error_message = "production workload workspaces must have speculative_enabled = false."
  }
}

run "production_flag_overrides_name" {
  command = plan

  variables {
    environments = {
      dev  = { is_production = true }
      prod = { is_production = false }
    }
  }

  assert {
    condition     = module.workspace["gcp-workload-dev"].speculative_enabled == false && module.workspace["aws-workload-prod"].speculative_enabled == true
    error_message = "an explicit is_production wins over the prod/production name heuristic."
  }
}

run "speculative_on_production_opt_out" {
  command = plan

  variables {
    disable_speculative_on_production = false
  }

  assert {
    condition     = module.workspace["gcp-workload-prod"].speculative_enabled == true && module.workspace["gcp-organization"].speculative_enabled == false
    error_message = "disable_speculative_on_production = false re-enables production speculative plans only."
  }
}

# Remote state: never global, and only the consumers derived from the envs/**
# terraform_remote_state reads may read a producer's state.
run "remote_state_consumer_graph" {
  command = plan

  assert {
    condition     = alltrue([for k, s in tfe_workspace_settings.this : s.global_remote_state == false])
    error_message = "global_remote_state must be false on every workspace."
  }

  assert {
    condition     = toset(output.remote_state_consumers["gcp-organization"]) == toset(["gcp-projects", "gcp-network-hub", "gcp-workload-dev", "gcp-workload-prod"])
    error_message = "gcp-organization state must be shared with gcp-projects, gcp-network-hub and every gcp-workload."
  }

  assert {
    condition     = toset(output.remote_state_consumers["gcp-network-hub"]) == toset(["gcp-workload-dev", "gcp-workload-prod"])
    error_message = "gcp-network-hub state must be shared with the gcp-workload workspaces only."
  }

  assert {
    condition     = toset(output.remote_state_consumers["gcp-bootstrap"]) == toset(["gcp-organization", "gcp-projects"])
    error_message = "gcp-bootstrap state must be shared with gcp-organization and gcp-projects."
  }

  assert {
    condition     = length(output.remote_state_consumers["aws-organization"]) == 7 && toset(output.remote_state_consumers["aws-security"]) == toset(["aws-workload-dev", "aws-workload-prod"])
    error_message = "aws-organization is read by every aws-* root; aws-security by the aws workloads."
  }

  # No consumer of a workload or of saas unless opted in (saas state holds secrets).
  assert {
    condition     = !contains(keys(output.remote_state_consumers), "saas-web") && !contains(keys(output.remote_state_consumers), "gcp-workload-dev")
    error_message = "saas and workload state must not be shared by default."
  }

  assert {
    condition     = length(tfe_workspace_settings.this["gcp-workload-dev"].remote_state_consumer_ids) == 0
    error_message = "a workspace with no readers must have an empty consumer list."
  }
}

run "extra_consumers_opt_in" {
  command = plan

  variables {
    extra_remote_state_consumers = { "saas-web" = ["gcp-workload-prod"] }
  }

  assert {
    condition     = output.remote_state_consumers["saas-web"] == tolist(["gcp-workload-prod"])
    error_message = "extra_remote_state_consumers must add the opt-in cross-cloud edge."
  }
}

run "extra_consumers_reject_unknown_workspace" {
  command = plan

  variables {
    extra_remote_state_consumers = { "saas-web" = ["gcp-workload-typo"] }
  }

  expect_failures = [terraform_data.input_contract]
}

# Dynamic credentials are NOT set when no inputs are supplied.
run "no_credential_env_without_inputs" {
  command = plan

  assert {
    condition     = length(output.dynamic_credential_workspaces.gcp) == 0 && length(output.dynamic_credential_workspaces.aws) == 0
    error_message = "no dynamic-credential env vars may be set without inputs."
  }

  assert {
    condition     = !contains(module.workspace["gcp-organization"].variable_keys, "TFC_GCP_PROVIDER_AUTH")
    error_message = "TFC_GCP_PROVIDER_AUTH must not be set when no SA is supplied."
  }

  # gcp-workload-<env> gets environment derived from its name.
  assert {
    condition     = module.workspace["gcp-workload-prod"].variable_keys == tolist(["environment"])
    error_message = "gcp-workload-<env> must receive the derived environment variable."
  }

  assert {
    condition     = module.workspace["gcp-organization"].variable_set_labels == tolist(["common"])
    error_message = "every workspace must have the shared common variable set attached."
  }
}

run "credential_env_set_per_workspace" {
  command = plan

  variables {
    gcp_workload_provider_name = "projects/123456789/locations/global/workloadIdentityPools/tfc-pool/providers/tfc-provider"
    gcp_plan_service_accounts  = { "gcp-organization" = "tfc-plan-org@admin-proj.iam.gserviceaccount.com" }
    gcp_apply_service_accounts = { "gcp-organization" = "tfc-apply-org@admin-proj.iam.gserviceaccount.com" }
    aws_plan_role_arns         = { "aws-network" = "arn:aws:iam::111111111111:role/tfc-plan" }
    aws_apply_role_arns        = { "aws-network" = "arn:aws:iam::111111111111:role/tfc-apply" }
    workspace_variables = {
      "aws-workload-dev" = { environment = { value = "dev-override" } }
    }
  }

  assert {
    condition = module.workspace["gcp-organization"].variable_keys == sort([
      "TFC_GCP_PROVIDER_AUTH", "TFC_GCP_WORKLOAD_PROVIDER_NAME",
      "TFC_GCP_PLAN_SERVICE_ACCOUNT_EMAIL", "TFC_GCP_APPLY_SERVICE_ACCOUNT_EMAIL",
    ])
    error_message = "a GCP workspace with SAs must get the four TFC_GCP_* env vars."
  }

  assert {
    condition     = module.workspace["aws-network"].variable_keys == sort(["TFC_AWS_PROVIDER_AUTH", "TFC_AWS_PLAN_ROLE_ARN", "TFC_AWS_APPLY_ROLE_ARN"])
    error_message = "an AWS workspace with roles must get the three TFC_AWS_* env vars."
  }

  assert {
    condition     = output.dynamic_credential_workspaces.gcp == tolist(["gcp-organization"]) && output.dynamic_credential_workspaces.aws == tolist(["aws-network"])
    error_message = "credentials must be set only on the workspaces named in the input maps."
  }

  assert {
    condition     = module.workspace["aws-workload-dev"].variable_keys == tolist(["environment"])
    error_message = "aws-workload-<env> must receive the derived environment variable."
  }
}

run "credential_maps_reject_wrong_cloud" {
  command = plan

  variables {
    aws_plan_role_arns  = { "gcp-organization" = "arn:aws:iam::111111111111:role/tfc-plan" }
    aws_apply_role_arns = { "gcp-organization" = "arn:aws:iam::111111111111:role/tfc-apply" }
  }

  expect_failures = [terraform_data.input_contract]
}

run "credential_maps_need_matching_keys" {
  command = plan

  variables {
    gcp_plan_service_accounts = { "gcp-organization" = "tfc-plan-org@admin-proj.iam.gserviceaccount.com" }
  }

  expect_failures = [var.gcp_apply_service_accounts]
}

# Second bootstrap pass: read gcp-bootstrap / aws-organization outputs from TFC.
run "credentials_from_upstream_outputs" {
  command = plan

  variables {
    gcp_bootstrap_outputs_from_tfc    = true
    aws_organization_outputs_from_tfc = true
    aws_workspace_account_keys        = { "aws-workload-prod" = "prod" }
  }

  override_data {
    target = data.tfe_outputs.gcp_bootstrap[0]
    values = {
      nonsensitive_values = {
        tfc_workload_provider_name = "projects/123456789/locations/global/workloadIdentityPools/tfc-pool/providers/tfc-provider"
        tfc_plan_service_accounts  = { "gcp-projects" = "tfc-plan-projects@admin-proj.iam.gserviceaccount.com" }
        tfc_apply_service_accounts = { "gcp-projects" = "tfc-apply-projects@admin-proj.iam.gserviceaccount.com" }
      }
    }
  }

  override_data {
    target = data.tfe_outputs.aws_organization[0]
    values = {
      nonsensitive_values = {
        tfc_plan_role_arns     = { prod = "arn:aws:iam::222222222222:role/tfc-plan", network = "arn:aws:iam::444444444444:role/tfc-plan", security_tooling = "arn:aws:iam::333333333333:role/tfc-plan" }
        tfc_apply_role_arns    = { prod = "arn:aws:iam::222222222222:role/tfc-apply", network = "arn:aws:iam::444444444444:role/tfc-apply", security_tooling = "arn:aws:iam::333333333333:role/tfc-apply" }
        tfc_workspace_bindings = { security_tooling = ["aws-security"], network = ["aws-network"] }
      }
    }
  }

  override_data {
    target = data.tfe_workspace.tfc_admin[0]
    values = { id = "ws-tfcadmin" }
  }

  # aws-security is a multi-account root: its binding must NOT turn the
  # security_tooling member role into its default credentials (the default is
  # the management account, and no management role is supplied here).
  assert {
    condition     = output.dynamic_credential_workspaces.gcp == tolist(["gcp-projects"]) && output.dynamic_credential_workspaces.aws == tolist(["aws-network", "aws-workload-prod"])
    error_message = "credentials read from upstream outputs must reach the single-account workspaces only (explicit aws_workspace_account_keys and derived tfc_workspace_bindings)."
  }

  # tfc-admin must be allowed to read the upstream states it pulls outputs from.
  assert {
    condition     = contains(tfe_workspace_settings.this["gcp-bootstrap"].remote_state_consumer_ids, "ws-tfcadmin") && contains(tfe_workspace_settings.this["aws-organization"].remote_state_consumer_ids, "ws-tfcadmin")
    error_message = "tfc-admin must be a remote-state consumer of gcp-bootstrap and aws-organization when reading their outputs."
  }
}

# Multi-account roots: default = management account, one TFC configuration per
# member-account alias derived from the aws-organization outputs.
run "multi_account_alias_credentials" {
  command = plan

  variables {
    aws_organization_outputs_from_tfc = true
    aws_management_plan_role_arn      = "arn:aws:iam::111111111111:role/tfc-mgmt-plan"
    aws_management_apply_role_arn     = "arn:aws:iam::111111111111:role/tfc-mgmt-apply"
  }

  override_data {
    target = data.tfe_outputs.aws_organization[0]
    values = {
      nonsensitive_values = {
        tfc_plan_role_arns = {
          security_tooling = "arn:aws:iam::333333333333:role/tfc-plan"
          log_archive      = "arn:aws:iam::555555555555:role/tfc-plan"
          forensics        = "arn:aws:iam::666666666666:role/tfc-plan"
        }
        tfc_apply_role_arns = {
          security_tooling = "arn:aws:iam::333333333333:role/tfc-apply"
          log_archive      = "arn:aws:iam::555555555555:role/tfc-apply"
          forensics        = "arn:aws:iam::666666666666:role/tfc-apply"
        }
        tfc_workspace_bindings = { security_tooling = ["aws-security"], log_archive = ["aws-security"], forensics = ["aws-security"] }
      }
    }
  }

  override_data {
    target = data.tfe_workspace.tfc_admin[0]
    values = { id = "ws-tfcadmin" }
  }

  assert {
    condition = module.workspace["aws-security"].variable_keys == sort(concat(
      ["TFC_AWS_PROVIDER_AUTH", "TFC_AWS_PLAN_ROLE_ARN", "TFC_AWS_APPLY_ROLE_ARN"],
      flatten([for a in ["security_tooling", "log_archive", "forensics"] : ["TFC_AWS_PROVIDER_AUTH_${a}", "TFC_AWS_PLAN_ROLE_ARN_${a}", "TFC_AWS_APPLY_ROLE_ARN_${a}"]]),
    ))
    error_message = "aws-security must get the default (management) config plus one TFC_AWS_*_<alias> set per member-account alias."
  }

  assert {
    condition     = module.workspace["aws-security"].variable_values["TFC_AWS_PLAN_ROLE_ARN"] == "arn:aws:iam::111111111111:role/tfc-mgmt-plan" && module.workspace["aws-security"].variable_values["TFC_AWS_APPLY_ROLE_ARN_log_archive"] == "arn:aws:iam::555555555555:role/tfc-apply"
    error_message = "the default config must be the management role and each alias its own member-account role."
  }

  # aws-organization gets the management role (single provider, no aliases);
  # aws-backup has no backup-account roles yet, so it is withheld entirely.
  assert {
    condition     = module.workspace["aws-organization"].variable_keys == sort(["TFC_AWS_PROVIDER_AUTH", "TFC_AWS_PLAN_ROLE_ARN", "TFC_AWS_APPLY_ROLE_ARN"])
    error_message = "aws-organization must get only the management-account default configuration."
  }

  assert {
    condition     = !contains(output.dynamic_credential_workspaces.aws, "aws-backup")
    error_message = "a multi-account workspace whose aliases are incomplete must receive no AWS credentials."
  }
}

# Aws-security / aws-backup get their own least-privilege management
# roles from aws-organization; only aws-organization keeps the shared one.
run "dedicated_management_roles_per_workspace" {
  command = plan

  variables {
    aws_organization_outputs_from_tfc = true
    aws_management_plan_role_arn      = "arn:aws:iam::111111111111:role/tfc-mgmt-plan"
    aws_management_apply_role_arn     = "arn:aws:iam::111111111111:role/tfc-mgmt-apply"
  }

  override_data {
    target = data.tfe_outputs.aws_organization[0]
    values = {
      nonsensitive_values = {
        tfc_plan_role_arns = {
          security_tooling = "arn:aws:iam::333333333333:role/tfc-plan"
          log_archive      = "arn:aws:iam::555555555555:role/tfc-plan"
          forensics        = "arn:aws:iam::666666666666:role/tfc-plan"
        }
        tfc_apply_role_arns = {
          security_tooling = "arn:aws:iam::333333333333:role/tfc-apply"
          log_archive      = "arn:aws:iam::555555555555:role/tfc-apply"
          forensics        = "arn:aws:iam::666666666666:role/tfc-apply"
        }
        tfc_workspace_bindings         = { security_tooling = ["aws-security"], log_archive = ["aws-security"], forensics = ["aws-security"] }
        tfc_management_plan_role_arns  = { "aws-security" = "arn:aws:iam::111111111111:role/tfc-mgmt-aws-security-plan" }
        tfc_management_apply_role_arns = { "aws-security" = "arn:aws:iam::111111111111:role/tfc-mgmt-aws-security-apply" }
      }
    }
  }

  override_data {
    target = data.tfe_workspace.tfc_admin[0]
    values = { id = "ws-tfcadmin" }
  }

  assert {
    condition = (
      module.workspace["aws-security"].variable_values["TFC_AWS_PLAN_ROLE_ARN"] == "arn:aws:iam::111111111111:role/tfc-mgmt-aws-security-plan" &&
      module.workspace["aws-security"].variable_values["TFC_AWS_APPLY_ROLE_ARN"] == "arn:aws:iam::111111111111:role/tfc-mgmt-aws-security-apply" &&
      module.workspace["aws-organization"].variable_values["TFC_AWS_APPLY_ROLE_ARN"] == "arn:aws:iam::111111111111:role/tfc-mgmt-apply"
    )
    error_message = "aws-security must use its dedicated management roles; aws-organization keeps the shared phase-0 role."
  }
}

run "explicit_alias_roles" {
  command = plan

  variables {
    aws_management_plan_role_arn  = "arn:aws:iam::111111111111:role/tfc-mgmt-plan"
    aws_management_apply_role_arn = "arn:aws:iam::111111111111:role/tfc-mgmt-apply"
    aws_alias_role_arns = {
      "aws-backup" = { backup = { plan_role_arn = "arn:aws:iam::777777777777:role/tfc-plan", apply_role_arn = "arn:aws:iam::777777777777:role/tfc-apply" } }
    }
  }

  assert {
    condition     = contains(module.workspace["aws-backup"].variable_keys, "TFC_AWS_APPLY_ROLE_ARN_backup") && length(module.workspace["aws-backup"].variable_keys) == 6
    error_message = "aws-backup must get the management default plus the backup alias configuration."
  }
}

run "multi_account_explicit_default_without_aliases_fails" {
  command = plan

  variables {
    aws_plan_role_arns  = { "aws-security" = "arn:aws:iam::111111111111:role/tfc-mgmt-plan" }
    aws_apply_role_arns = { "aws-security" = "arn:aws:iam::111111111111:role/tfc-mgmt-apply" }
  }

  expect_failures = [terraform_data.input_contract]
}

run "alias_role_unknown_alias_fails" {
  command = plan

  variables {
    aws_alias_role_arns = {
      "aws-security" = { typo = { plan_role_arn = "arn:aws:iam::777777777777:role/tfc-plan", apply_role_arn = "arn:aws:iam::777777777777:role/tfc-apply" } }
    }
  }

  expect_failures = [terraform_data.input_contract]
}

run "account_key_rejected_for_management_workspace" {
  command = plan

  variables {
    aws_workspace_account_keys = { "aws-security" = "security_tooling" }
  }

  expect_failures = [terraform_data.input_contract]
}

# environments[*].aws_account_key wires aws-workload-<env>: workload_account_key
# variable plus that account's roles from the aws-organization outputs.
run "aws_workload_account_binding" {
  command = plan

  variables {
    environments = {
      dev  = { aws_account_key = "workload_dev" }
      prod = {}
    }
    aws_organization_outputs_from_tfc = true
  }

  override_data {
    target = data.tfe_outputs.aws_organization[0]
    values = {
      nonsensitive_values = {
        tfc_plan_role_arns     = { workload_dev = "arn:aws:iam::888888888888:role/tfc-plan" }
        tfc_apply_role_arns    = { workload_dev = "arn:aws:iam::888888888888:role/tfc-apply" }
        tfc_workspace_bindings = {}
      }
    }
  }

  override_data {
    target = data.tfe_workspace.tfc_admin[0]
    values = { id = "ws-tfcadmin" }
  }

  assert {
    condition     = module.workspace["aws-workload-dev"].variable_values["workload_account_key"] == "workload_dev" && module.workspace["aws-workload-dev"].variable_values["environment"] == "dev" && module.workspace["aws-workload-dev"].variable_values["TFC_AWS_PLAN_ROLE_ARN"] == "arn:aws:iam::888888888888:role/tfc-plan"
    error_message = "aws-workload-dev must get environment, workload_account_key and the bound account's roles."
  }

  assert {
    condition     = module.workspace["aws-workload-prod"].variable_keys == tolist(["environment"])
    error_message = "an environment without aws_account_key only gets the derived environment variable."
  }
}

# GCP phase-0: gcp-bootstrap runs locally (operator ADC) by default; every other
# workspace stays remote.
run "execution_mode_overrides" {
  command = plan

  assert {
    condition     = tfe_workspace_settings.this["gcp-bootstrap"].execution_mode == "local" && tfe_workspace_settings.this["gcp-organization"].execution_mode == "remote" && tfe_workspace_settings.this["aws-organization"].execution_mode == "remote"
    error_message = "gcp-bootstrap must default to local execution and every other workspace to remote."
  }
}

run "execution_mode_switch_to_remote_after_second_pass" {
  command = plan

  variables {
    workspace_execution_modes = {}
  }

  assert {
    condition     = alltrue([for k, m in output.workspace_execution_modes : m == "remote"])
    error_message = "with no overrides every workspace runs remotely."
  }
}

run "execution_mode_local_rejected_outside_phase0" {
  command = plan

  variables {
    workspace_execution_modes = { "gcp-organization" = "local" }
  }

  expect_failures = [var.workspace_execution_modes]
}

run "at_least_one_cloud_required" {
  command = plan

  variables {
    enable_gcp  = false
    enable_aws  = false
    enable_saas = false
  }

  expect_failures = [var.enable_gcp]
}

# Committed per-workspace variables for VCS-driven runs.
run "workspace_variables_file_loaded" {
  command = plan

  variables {
    workspace_variables_file = "tests/fixtures/tfc-workspaces.yaml"
    workspace_variables = {
      "gcp-organization" = { domain = { value = "override.example" } }
    }
  }

  assert {
    condition     = output.workspace_variables_file_loaded && module.workspace["aws-network"].variable_values["name_prefix"] == "acme" && module.workspace["aws-network"].variable_values["allowed_regions"] == jsonencode(["eu-west-2", "eu-west-1"])
    error_message = "scalar and list entries from the committed file must reach the workspace (lists as HCL)."
  }

  assert {
    condition     = module.workspace["gcp-organization"].variable_values["domain"] == "override.example"
    error_message = "workspace_variables must win over the committed file."
  }
}

run "workspace_variables_file_missing_is_noop" {
  command = plan

  variables {
    workspace_variables_file = "tests/fixtures/does-not-exist.yaml"
  }

  assert {
    condition     = !output.workspace_variables_file_loaded
    error_message = "a missing workspace_variables_file must be ignored."
  }
}

run "workspace_variables_file_rejects_secrets" {
  command = plan

  variables {
    workspace_variables_file = "tests/fixtures/tfc-workspaces-sensitive.yaml"
  }

  expect_failures = [terraform_data.input_contract]
}

run "workspace_variables_file_rejects_reserved_env" {
  command = plan

  variables {
    workspace_variables_file = "tests/fixtures/tfc-workspaces-reserved-env.yaml"
  }

  expect_failures = [terraform_data.input_contract]
}

# Control-plane run notifications: a configured control-plane
# notification reaches foundational workspaces but not workload workspaces.
run "control_plane_notifications_routed_by_tag" {
  command = plan

  variables {
    enable_aws  = false
    enable_saas = false
    control_plane_notifications = {
      cp-webhook = { destination_type = "generic", url = "https://example.com/hooks/ci" }
    }
  }

  assert {
    condition     = length(module.workspace["gcp-organization"].notification_ids) == 1
    error_message = "control-plane workspaces must receive the control_plane_notifications."
  }

  assert {
    condition     = length(module.workspace["gcp-workload-dev"].notification_ids) == 0
    error_message = "workload workspaces must not receive control-plane notifications unless opted in."
  }
}

# The broad platform team gets only custom plan-level access on projects
# holding the control plane (no variable edits, no apply); a separate approvers
# team confirms control-plane applies; workload projects keep fixed write.
run "team_access_least_privilege" {
  command = plan

  variables {
    platform_team_id                = "team-platform1"
    control_plane_approvers_team_id = "team-approvers1"
    viewer_team_ids                 = ["team-viewers1"]
  }

  assert {
    condition = alltrue([
      for p in ["gcp", "aws"] :
      tfe_team_project_access.this["${p}/platform"].access == "custom" &&
      tfe_team_project_access.this["${p}/platform"].workspace_access[0].runs == "plan" &&
      tfe_team_project_access.this["${p}/platform"].workspace_access[0].variables == "read" &&
      tfe_team_project_access.this["${p}/platform"].workspace_access[0].policy_overrides == false &&
      tfe_team_project_access.this["${p}/platform"].workspace_access[0].delete == false &&
      tfe_team_project_access.this["${p}/platform"].project_access[0].teams == "none"
    ])
    error_message = "on control-plane projects the platform team must get custom access: runs = plan, variables = read, no overrides/delete/team management."
  }

  assert {
    condition = alltrue([
      for p in ["gcp", "aws"] :
      tfe_team_project_access.this["${p}/approvers"].access == "custom" &&
      tfe_team_project_access.this["${p}/approvers"].workspace_access[0].runs == "apply" &&
      tfe_team_project_access.this["${p}/approvers"].workspace_access[0].variables == "read" &&
      tfe_team_project_access.this["${p}/approvers"].team_id == "team-approvers1"
    ]) && !contains(keys(tfe_team_project_access.this), "saas/approvers")
    error_message = "the approvers team must get runs = apply (variables read-only) on every control-plane project and nowhere else."
  }

  assert {
    condition     = tfe_team_project_access.this["saas/platform"].access == "write" && tfe_team_project_access.this["aws/team-viewers1"].access == "read"
    error_message = "workload-only projects keep platform write; viewer teams get read on every project."
  }

  # 3 projects x (platform + viewer) + 2 control-plane projects x approvers +
  # the security team on the guardrails project = 9.
  assert {
    condition     = length(tfe_team_project_access.this) == 9
    error_message = "3 x (platform + viewer) + 2 approvers + 1 security = 9 project grants."
  }

  # Workload workspaces sharing a project with the control plane get write
  # through a workspace-level grant; control-plane workspaces never do.
  assert {
    condition     = toset(keys(tfe_team_access.platform_workload)) == toset(["gcp-workload-dev", "gcp-workload-prod", "aws-workload-dev", "aws-workload-prod"]) && alltrue([for g in values(tfe_team_access.platform_workload) : g.access == "write" && g.team_id == "team-platform1"])
    error_message = "only the gcp/aws workload workspaces get a workspace-level platform write grant."
  }
}

# gcp-guardrails (the org IAM deny policies) lives in its own project where
# only the security team has access: no platform, approvers or viewer grant,
# no speculative plans, no auto-apply, no UI destroy plans.
run "guardrails_project_security_team_only" {
  command = plan

  variables {
    platform_team_id                = "team-platform1"
    control_plane_approvers_team_id = "team-approvers1"
    viewer_team_ids                 = ["team-viewers1"]
    security_team_id                = "team-security1"
  }

  assert {
    condition     = contains(keys(tfe_project.this), "guardrails") && tfe_project.this["guardrails"].name == "landing-zone-guardrails" && module.workspace["gcp-guardrails"].working_directory == "envs/gcp/guardrails"
    error_message = "gcp-guardrails must live in its own <prefix>guardrails project."
  }

  assert {
    condition     = jsonencode([for k, g in tfe_team_project_access.this : g.team_id if startswith(k, "guardrails/")]) == jsonencode(["team-security1"])
    error_message = "the security team must be the only team with access to the guardrails project."
  }

  assert {
    condition     = tfe_team_project_access.this["guardrails/security"].access == "custom" && tfe_team_project_access.this["guardrails/security"].workspace_access[0].runs == "apply" && tfe_team_project_access.this["guardrails/security"].workspace_access[0].variables == "read" && tfe_team_project_access.this["guardrails/security"].project_access[0].teams == "none"
    error_message = "the security team must be able to queue and confirm applies on gcp-guardrails (runs = apply), with variables read-only and no team management."
  }

  assert {
    condition     = length([for k, g in tfe_team_project_access.this : k if g.team_id == "team-security1"]) == 1
    error_message = "the security team gets no grant on the other projects through this root."
  }

  assert {
    condition     = module.workspace["gcp-guardrails"].speculative_enabled == false && module.workspace["gcp-guardrails"].auto_apply == false && module.workspace["gcp-guardrails"].allow_destroy_plan == false
    error_message = "gcp-guardrails must run without speculative plans, auto-apply or UI destroy plans."
  }

  assert {
    condition     = contains(output.never_auto_apply_workspaces, "gcp-guardrails") && !contains(keys(tfe_team_access.platform_workload), "gcp-guardrails")
    error_message = "gcp-guardrails must be excluded from any auto-apply and from workspace-level platform grants."
  }

  # The platform-controlled common variable set must not reach the security
  # team's workspace (it could inject containment_exempt_principals).
  assert {
    condition     = length(module.workspace["gcp-guardrails"].variable_set_labels) == 0 && module.workspace["gcp-organization"].variable_set_labels == tolist(["common"])
    error_message = "gcp-guardrails must not have the common variable set attached."
  }

  assert {
    condition     = length(lookup(output.remote_state_consumers, "gcp-guardrails", [])) == 0 && !contains(flatten(values(output.remote_state_consumers)), "gcp-guardrails")
    error_message = "gcp-guardrails reads no other state and shares none."
  }
}

# Without a security team the guardrails project has no team grant at all
# (organization owners only), and the plan warns.
run "guardrails_project_without_security_team_warns" {
  command = plan

  variables {
    platform_team_id = "team-platform1"
    security_team_id = null
  }

  assert {
    condition     = length([for k, g in tfe_team_project_access.this : k if startswith(k, "guardrails/")]) == 0
    error_message = "without security_team_id no team may get access to the guardrails project."
  }

  expect_failures = [check.guardrails_project_has_security_team]
}

run "security_team_must_differ_from_platform" {
  command = plan

  variables {
    platform_team_id = "team-same1"
    security_team_id = "team-same1"
  }

  expect_failures = [terraform_data.input_contract]
}

run "platform_team_runs_override" {
  command = plan

  variables {
    platform_team_id                 = "team-platform1"
    platform_team_control_plane_runs = "read"
  }

  assert {
    condition     = tfe_team_project_access.this["gcp/platform"].workspace_access[0].runs == "read" && length([for k in keys(tfe_team_project_access.this) : k if endswith(k, "/approvers")]) == 0
    error_message = "platform_team_control_plane_runs sets the platform runs level; no approvers grant without control_plane_approvers_team_id."
  }
}

run "approvers_must_differ_from_platform" {
  command = plan

  variables {
    platform_team_id                = "team-same1"
    control_plane_approvers_team_id = "team-same1"
  }

  expect_failures = [terraform_data.input_contract]
}

# Opt-in split: workload workspaces move to <prefix><cloud>-workloads projects,
# which get fixed platform write; control-plane projects stay custom.
run "split_workload_projects" {
  command = plan

  variables {
    split_workload_projects         = true
    platform_team_id                = "team-platform1"
    control_plane_approvers_team_id = "team-approvers1"
  }

  assert {
    condition     = toset(keys(tfe_project.this)) == toset(["gcp", "aws", "saas", "gcp-workloads", "aws-workloads", "guardrails"]) && tfe_project.this["gcp-workloads"].name == "landing-zone-gcp-workloads" && tfe_project.this["aws"].name == "landing-zone-aws"
    error_message = "split mode adds <prefix>gcp-workloads / <prefix>aws-workloads and keeps the control-plane project names."
  }

  assert {
    condition     = tfe_team_project_access.this["gcp-workloads/platform"].access == "write" && tfe_team_project_access.this["gcp/platform"].access == "custom" && !contains(keys(tfe_team_project_access.this), "aws-workloads/approvers")
    error_message = "workload projects get fixed platform write; only control-plane projects get custom + approvers."
  }

  assert {
    condition     = length(tfe_team_access.platform_workload) == 0
    error_message = "no workspace-level grants are needed once workloads have their own project."
  }
}

run "policy_set_optional_and_advisory_source" {
  command = plan

  variables {
    enable_policy_sets         = true
    vcs_repo                   = { identifier = "acme/landing-zone", oauth_token_id = "ot-abc123" }
    manage_tfc_admin_workspace = true
    import_tfc_admin_workspace = false
  }

  assert {
    condition     = tfe_policy_set.opa[0].kind == "opa" && tfe_policy_set.opa[0].policies_path == "policies/opa"
    error_message = "the policy set must be an OPA set sourced from policies/opa."
  }

  assert {
    condition     = tfe_policy_set.opa[0].overridable == false
    error_message = "mandatory policies must not be overridable by default."
  }
}

run "speculative_on_saas_opt_out" {
  command = plan

  variables {
    disable_speculative_on_saas = false
  }

  assert {
    condition     = module.workspace["saas-web"].speculative_enabled == true
    error_message = "disable_speculative_on_saas = false re-enables SaaS speculative plans."
  }
}

# enable_policy_sets = null with no vcs_repo (and no org.tfc.plan): both sets
# stay off and a check warns that destructive changes are unguarded.
run "policy_sets_off_without_vcs_repo_warns" {
  command = plan

  variables {
    enable_unguarded_destroy_warning = true
  }

  assert {
    condition     = length(tfe_policy_set.opa) == 0 && length(tfe_policy_set.destructive) == 0
    error_message = "without vcs_repo and a plan that supports VCS policy sets, no policy set is created."
  }

  expect_failures = [check.destructive_changes_guarded]
}

# The guardrails set stays a hard gate; the destroy guard is mandatory but
# overridable (by the security team holding Manage Policy Overrides).
run "destructive_set_overridable_main_set_not" {
  command = plan

  variables {
    enable_policy_sets         = true
    vcs_repo                   = { identifier = "acme/landing-zone", oauth_token_id = "ot-abc123" }
    manage_tfc_admin_workspace = true
    import_tfc_admin_workspace = false
  }

  assert {
    condition     = tfe_policy_set.opa[0].overridable == false
    error_message = "the guardrails set must not be overridable."
  }

  assert {
    condition     = tfe_policy_set.destructive[0].overridable == true && tfe_policy_set.destructive[0].kind == "opa" && tfe_policy_set.destructive[0].policies_path == "policies/opa-destructive"
    error_message = "the destructive-change guard must be an overridable OPA set sourced from policies/opa-destructive."
  }

  assert {
    condition     = tfe_policy_set.destructive[0].name == "landing-zone-destructive-change-guard" && tfe_policy_set.destructive[0].vcs_repo[0].identifier == "acme/landing-zone" && tfe_policy_set.destructive[0].policy_tool_version == tfe_policy_set.opa[0].policy_tool_version
    error_message = "the destructive set is <prefix>destructive-change-guard, from the same repo and OPA version as the guardrails set."
  }

  assert {
    condition     = length(local.policy_set_workspace_ids) == length(module.workspace)
    error_message = "both sets attach to every managed workspace (local.policy_set_workspace_ids; the IDs are unknown at plan)."
  }
}

# Policy-set overrides are org-wide and granted by an owner in the HCP UI to
# the hand-created security team; without security_team_id a check warns.
run "destructive_set_without_security_team_warns" {
  command = plan

  variables {
    enable_policy_sets         = true
    vcs_repo                   = { identifier = "acme/landing-zone", oauth_token_id = "ot-abc123" }
    manage_tfc_admin_workspace = true
    import_tfc_admin_workspace = false
    security_team_id           = null
  }

  # gcp-guardrails also loses its team, so that check warns too.
  expect_failures = [check.destructive_override_team, check.guardrails_project_has_security_team]
}

# An unmanaged tfc-admin with a VCS connection keeps speculative plans on, so
# a PR plan could read its org-admin TFE_TOKEN: the check must warn.
run "unmanaged_vcs_tfc_admin_warns" {
  command = plan

  variables {
    vcs_repo = { identifier = "acme/landing-zone", oauth_token_id = "ot-abc123" }
  }

  expect_failures = [check.tfc_admin_workspace_hardened]
}

run "self_management_adopts_tfc_admin" {
  command = plan

  variables {
    manage_tfc_admin_workspace = true
    # Mock providers cannot import; the import block itself is exercised by
    # the adopting apply in TFC.
    import_tfc_admin_workspace = false
  }

  assert {
    condition     = module.workspace["tfc-admin"].speculative_enabled == false && toset(module.workspace["tfc-admin"].trigger_patterns) == toset(["envs/tfc-admin/**", "modules/tfc/**", "config/landing-zone.yaml"])
    error_message = "a self-managed tfc-admin workspace is control plane: no speculative plans, triggers on its dir + modules/tfc + the estate config."
  }

  assert {
    condition     = contains(keys(tfe_project.this), "platform")
    error_message = "self-managed tfc-admin lands in the platform project."
  }
}

# tfc-admin holds the TFE_TOKEN: its applies are confirmed by owners and the
# tfc-admin team only. Never auto-applied, and neither the approvers team nor a
# platform team that may apply control-plane roots gets apply on the platform
# project (it holds only this workspace).
run "tfc_admin_workspace_apply_restricted" {
  command = plan

  variables {
    manage_tfc_admin_workspace       = true
    import_tfc_admin_workspace       = false
    tfc_admin_team_id                = "team-tfcadmin1"
    platform_team_id                 = "team-platform1"
    control_plane_approvers_team_id  = "team-approvers1"
    platform_team_control_plane_runs = "apply"
  }

  assert {
    condition     = module.workspace["tfc-admin"].auto_apply == false && module.workspace["tfc-admin"].auto_apply_run_trigger == false && module.workspace["tfc-admin"].speculative_enabled == false
    error_message = "tfc-admin must never auto-apply and must not run speculative plans."
  }

  assert {
    condition     = tfe_team_access.tfc_admin[0].team_id == "team-tfcadmin1" && tfe_team_access.tfc_admin[0].access == "write"
    error_message = "the tfc-admin team gets explicit write (apply) on the tfc-admin workspace."
  }

  assert {
    condition     = !contains(keys(tfe_team_project_access.this), "platform/approvers") && tfe_team_project_access.this["platform/platform"].workspace_access[0].runs == "plan"
    error_message = "on the platform project (tfc-admin only) the approvers team gets no grant and the platform team is capped at plan."
  }

  assert {
    condition     = contains(keys(tfe_team_project_access.this), "gcp/approvers") && tfe_team_project_access.this["gcp/platform"].workspace_access[0].runs == "apply"
    error_message = "other control-plane projects are unchanged."
  }
}

# gcp-bootstrap receives every gcp-* workspace ID so its WIF bindings are by ID.
run "gcp_bootstrap_gets_workspace_ids" {
  command = plan

  assert {
    condition = (
      length(tfe_variable.gcp_bootstrap_workspace_ids) == 1 &&
      tfe_variable.gcp_bootstrap_workspace_ids[0].key == "tfc_workspace_ids" &&
      tfe_variable.gcp_bootstrap_workspace_ids[0].hcl == true &&
      startswith(output.gcp_bootstrap_tfvars, "tfc_workspace_ids = ")
    )
    error_message = "tfc-admin must set tfc_workspace_ids (HCL) on gcp-bootstrap and output the phase-0 tfvars line."
  }
}

run "gcp_bootstrap_workspace_ids_opt_out" {
  command = plan

  variables {
    set_gcp_bootstrap_workspace_ids = false
  }

  assert {
    condition     = length(tfe_variable.gcp_bootstrap_workspace_ids) == 0
    error_message = "set_gcp_bootstrap_workspace_ids = false must not write the variable."
  }
}

# Run triggers follow the dependency DAG's direct edges only.
run "run_triggers_follow_the_dag" {
  command = plan

  assert {
    condition = (
      contains(output.run_triggers, "gcp-projects->gcp-network-hub") &&
      contains(output.run_triggers, "gcp-network-hub->gcp-workload-dev") &&
      contains(output.run_triggers, "aws-network->aws-workload-prod") &&
      contains(output.run_triggers, "aws-organization->aws-security") &&
      !contains(output.run_triggers, "gcp-organization->gcp-workload-dev")
    )
    error_message = "run triggers must chain each root to its direct upstream, without transitive edges."
  }
}

run "run_triggers_opt_out" {
  command = plan

  variables {
    enable_run_triggers = false
  }

  assert {
    condition     = length(output.run_triggers) == 0
    error_message = "enable_run_triggers = false must create no run triggers."
  }
}
