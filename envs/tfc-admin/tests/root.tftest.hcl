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
    dev  = { is_production = false }
    prod = { is_production = true }
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

# Module-only PRs must trigger plans, but only where the module is used: each
# workspace watches its own dir, the module trees its root composes (directly
# or through a stage; root_trigger_dirs) and its estate's config files
# (sandbox.tftest.hcl covers the per-estate split).
run "trigger_patterns_cover_composed_modules" {
  command = plan

  assert {
    condition = toset(module.workspace["gcp-bootstrap"].trigger_patterns) == toset([
      "envs/gcp/bootstrap/**",
      "modules/gcp/iam/service-account/**", "modules/gcp/iam/workload-identity/**",
      "modules/gcp/project/**", "modules/gcp/stages/bootstrap/**",
      "config/landing-zone.yaml",
    ])
    error_message = "gcp-bootstrap must trigger on its dir, the four module trees it composes and the estate config, nothing else."
  }

  assert {
    condition = alltrue([
      for p in ["modules/gcp/stages/organization/**", "modules/gcp/stages/guardrails/**", "modules/gcp/governance/kms/**", "envs/gcp/organization/**", "config/landing-zone.yaml"] :
      contains(module.workspace["gcp-organization"].trigger_patterns, p)
    ])
    error_message = "gcp-organization must trigger on its stage and the modules the stage composes."
  }

  # A network or workload module change no longer queues the privileged
  # bootstrap and organization roots.
  assert {
    condition = alltrue([
      for ws in ["gcp-bootstrap", "gcp-organization", "gcp-projects", "aws-organization", "aws-identity"] :
      !anytrue([for p in module.workspace[ws].trigger_patterns : startswith(p, "modules/gcp/network/") || startswith(p, "modules/aws/network/") || startswith(p, "modules/gcp/compute/") || p == "modules/gcp/**" || p == "modules/aws/**"])
    ])
    error_message = "control-plane roots that compose no network or compute module must not trigger on those trees (or on a whole cloud's modules/**)."
  }

  assert {
    condition = alltrue([
      for p in ["envs/gcp/workload/**", "modules/gcp/stages/environment/**", "modules/gcp/stages/net-spoke/**", "modules/gcp/network/tiered-vpc/**", "examples/presets/**"] :
      contains(module.workspace["gcp-workload-dev"].trigger_patterns, p)
    ]) && module.workspace["gcp-workload-dev"].trigger_patterns == module.workspace["gcp-workload-prod"].trigger_patterns
    error_message = "every gcp-workload-<env> must trigger on the environment composition (stage, spoke network, tiered VPC) and on the preset files its config reads."
  }

  assert {
    condition     = contains(module.workspace["aws-workload-dev"].trigger_patterns, "modules/aws/stages/workload/**") && contains(module.workspace["aws-workload-dev"].trigger_patterns, "modules/aws/stages/app-services/**") && !contains(module.workspace["aws-workload-dev"].trigger_patterns, "modules/aws/stages/organization/**")
    error_message = "aws-workload-<env> must trigger on the workload and app-services stages, not on the organization stage."
  }

  assert {
    condition = toset(module.workspace["saas-web"].trigger_patterns) == toset([
      "envs/saas/**", "modules/saas/stages/saas-workload/**",
      "modules/supabase/environment/**", "modules/supabase/project/**", "modules/supabase/settings/**",
      "modules/supabase/vault-secrets/**", "modules/vercel/project/**",
      "config/landing-zone.yaml",
    ])
    error_message = "the saas root must trigger on envs/saas and the saas, supabase and vercel modules it composes."
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
    error_message = "is_production alone decides production; the key name is not read."
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
    # Pass 2 (bootstrap.md): gcp-bootstrap moves to remote execution.
    workspace_execution_modes  = {}
    aws_workspace_account_keys = { "aws-workload-prod" = "prod" }
  }

  override_data {
    target = data.tfe_outputs.gcp_bootstrap[0]
    values = {
      nonsensitive_values = {
        contract = {
          tfc_workload_provider_name = "projects/123456789/locations/global/workloadIdentityPools/tfc-pool/providers/tfc-provider"
          tfc_plan_service_accounts  = { "gcp-projects" = "tfc-plan-projects@admin-proj.iam.gserviceaccount.com" }
          tfc_apply_service_accounts = { "gcp-projects" = "tfc-apply-projects@admin-proj.iam.gserviceaccount.com" }
        }
      }
    }
  }

  override_data {
    target = data.tfe_outputs.aws_organization[0]
    values = {
      nonsensitive_values = {
        contract = {
          tfc_plan_role_arns     = { prod = "arn:aws:iam::222222222222:role/tfc-plan", network = "arn:aws:iam::444444444444:role/tfc-plan", security_tooling = "arn:aws:iam::333333333333:role/tfc-plan" }
          tfc_apply_role_arns    = { prod = "arn:aws:iam::222222222222:role/tfc-apply", network = "arn:aws:iam::444444444444:role/tfc-apply", security_tooling = "arn:aws:iam::333333333333:role/tfc-apply" }
          tfc_workspace_bindings = { security_tooling = ["aws-security"], network = ["aws-network"] }
        }
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

# N-1 upgrade: upstream states written before the `contract` output existed
# (individual outputs only) still resolve the same credentials. The fallback
# goes at v1.0 (UPGRADING.md).
run "credentials_from_pre_contract_upstream_outputs" {
  command = plan

  variables {
    gcp_bootstrap_outputs_from_tfc    = true
    aws_organization_outputs_from_tfc = true
    workspace_execution_modes         = {}
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
        tfc_plan_role_arns     = { prod = "arn:aws:iam::222222222222:role/tfc-plan", network = "arn:aws:iam::444444444444:role/tfc-plan" }
        tfc_apply_role_arns    = { prod = "arn:aws:iam::222222222222:role/tfc-apply", network = "arn:aws:iam::444444444444:role/tfc-apply" }
        tfc_workspace_bindings = { network = ["aws-network"] }
      }
    }
  }

  override_data {
    target = data.tfe_workspace.tfc_admin[0]
    values = { id = "ws-tfcadmin" }
  }

  assert {
    condition     = output.dynamic_credential_workspaces.gcp == tolist(["gcp-projects"]) && output.dynamic_credential_workspaces.aws == tolist(["aws-network", "aws-workload-prod"])
    error_message = "pre-contract upstream outputs must still resolve the dynamic credentials."
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
        contract = {
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
        contract = {
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
      dev  = { is_production = false, aws_account_key = "workload_dev" }
      prod = { is_production = true }
    }
    aws_organization_outputs_from_tfc = true
  }

  override_data {
    target = data.tfe_outputs.aws_organization[0]
    values = {
      nonsensitive_values = {
        contract = {
          tfc_plan_role_arns     = { workload_dev = "arn:aws:iam::888888888888:role/tfc-plan" }
          tfc_apply_role_arns    = { workload_dev = "arn:aws:iam::888888888888:role/tfc-apply" }
          tfc_workspace_bindings = {}
        }
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

# Every reserved name, one key at a time: credential redirection through the
# tfe provider, the CLI config, host tokens, proxies (any case) and CA bundles.
run "reserved_env_pattern_covers_redirection_vars" {
  command = plan

  assert {
    condition = alltrue([for k in [
      "TFE_TOKEN", "TFE_HOSTNAME", "TF_TOKEN_app_terraform_io", "TF_CLI_CONFIG_FILE",
      "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
      "http_proxy", "https_proxy", "all_proxy", "no_proxy", "Https_Proxy",
      "SSL_CERT_FILE", "SSL_CERT_DIR",
      "TFC_AWS_APPLY_ROLE_ARN", "TF_CLI_ARGS_plan", "AWS_PROFILE",
    ] : can(regex(local.reserved_env_pattern, k))])
    error_message = "a credential- or traffic-redirecting env var is not reserved."
  }

  assert {
    condition = !anytrue([for k in [
      "TF_PARALLELISM_HINT", "MY_HTTP_PROXY_NOTE", "NODE_OPTIONS_X", "APP_NAME", "no_proxy_list",
    ] : can(regex(local.reserved_env_pattern, k))])
    error_message = "an ordinary env var name is treated as reserved."
  }
}

# The committed file that sets only the new reserved names still fails.
run "workspace_variables_file_rejects_redirection_env" {
  command = plan

  variables {
    workspace_variables_file = "tests/fixtures/tfc-workspaces-redirect-env.yaml"
  }

  expect_failures = [terraform_data.input_contract]
}

# Env vars that make the runner execute other code (loader, interpreter,
# shell and git hooks, the CLI config) are refused from both sources: the
# committed file and workspace_variables.
run "code_exec_env_pattern_covers_loader_and_interpreter_vars" {
  command = plan

  assert {
    condition = alltrue([for k in [
      "TERRAFORM_CONFIG", "TF_CLI_CONFIG_FILE", "LD_PRELOAD", "LD_LIBRARY_PATH", "LD_AUDIT",
      "DYLD_INSERT_LIBRARIES", "DYLD_LIBRARY_PATH", "NODE_OPTIONS", "NODE_PATH",
      "GIT_CONFIG_GLOBAL", "GIT_CONFIG_COUNT", "GIT_CONFIG_KEY_0", "GIT_SSH_COMMAND", "GIT_SSH", "GIT_ASKPASS",
      "BASH_ENV", "ENV", "PYTHONPATH", "PYTHONSTARTUP", "PYTHONHOME", "PATH",
      "SHELLOPTS", "PS4", "BASH_FUNC_foo%%", "GCONV_PATH", "SSH_ASKPASS", "SSH_ASKPASS_REQUIRE",
      "PERL5OPT", "PERL5LIB", "RUBYOPT", "RUBYLIB", "JAVA_TOOL_OPTIONS", "_JAVA_OPTIONS",
    ] : can(regex(local.code_exec_env_pattern, k)) && can(regex(local.reserved_env_pattern, k))])
    error_message = "an env var that runs other code is not reserved in both patterns."
  }

  assert {
    condition     = can(regex(local.reserved_env_pattern, "NODE_EXTRA_CA_CERTS"))
    error_message = "NODE_EXTRA_CA_CERTS re-trusts HTTPS for node and must be reserved in the committed file."
  }

  # The documented workspace_variables uses stay open: tokens for the tfe,
  # Supabase and Vercel providers, TF_CLI_ARGS_plan (add-environment.md) and
  # dynamic-credential overrides and a corporate proxy or CA bundle.
  # tfc_admin_guard flags TFC_* and TF_CLI_ARGS*.
  assert {
    condition = !anytrue([for k in [
      "TFE_TOKEN", "SUPABASE_ACCESS_TOKEN", "VERCEL_API_TOKEN", "TF_CLI_ARGS_plan", "TFC_AWS_APPLY_ROLE_ARN",
      "HTTPS_PROXY", "SSL_CERT_FILE", "NODE_EXTRA_CA_CERTS",
      "NODE_OPTIONS_X", "ENVIRONMENT", "APP_ENV", "PATHS", "MY_PATH", "LD", "GITHUB_REPO",
      "HOME", "XDG_CONFIG_HOME", "PS1", "JAVA_HOME",
    ] : can(regex(local.code_exec_env_pattern, k))])
    error_message = "a documented workspace_variables env var or an ordinary name is refused."
  }
}

run "workspace_variables_rejects_code_exec_env" {
  command = plan

  variables {
    workspace_variables = {
      "aws-network" = {
        LD_PRELOAD = { value = "/tmp/evil.so", category = "env" }
      }
      "gcp-organization" = {
        NODE_OPTIONS = { value = "--require /tmp/evil.js", category = "env" }
      }
    }
  }

  expect_failures = [terraform_data.input_contract]
}

run "workspace_variables_file_rejects_code_exec_env" {
  command = plan

  variables {
    workspace_variables_file = "tests/fixtures/tfc-workspaces-exec-env.yaml"
  }

  expect_failures = [terraform_data.input_contract]
}

# A terraform-category variable with the same name is an input, not an env
# var, and stays allowed.
run "workspace_variables_terraform_category_named_like_env_allowed" {
  command = plan

  variables {
    workspace_variables = {
      "aws-network" = {
        PATH             = { value = "x", category = "terraform" }
        TF_CLI_ARGS_plan = { value = "-var-file=../../../examples/staging.tfvars", category = "env" }
      }
    }
  }

  assert {
    condition     = length(local.workspace_variables_exec_entries) == 0
    error_message = "a terraform-category input or a documented env var must not be refused."
  }
}

# gcp-guardrails is security_only: the platform-editable committed file must
# not reach it (its inputs live in its security-owned root).
run "workspace_variables_file_rejects_security_only_workspace" {
  command = plan

  variables {
    workspace_variables_file = "tests/fixtures/tfc-workspaces-security-only.yaml"
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

  # saas applies are confirmed by the control-plane approvers team.
  expect_failures = [check.saas_approvers_dedicated]

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
    ]) && tfe_team_project_access.this["saas/approvers"].workspace_access[0].runs == "apply"
    error_message = "the approvers team must get runs = apply (variables read-only) on every control-plane project and on the saas project."
  }

  assert {
    condition     = tfe_team_project_access.this["aws/team-viewers1"].access == "read"
    error_message = "viewer teams get fixed read on every project without secrets in state."
  }

  # The saas project holds account-wide Supabase/Vercel tokens: a plan (also a
  # CLI speculative plan with unreviewed configuration) can read them, so the
  # platform team may view runs there but never queue one.
  assert {
    condition = (
      tfe_team_project_access.this["saas/platform"].access == "custom" &&
      tfe_team_project_access.this["saas/platform"].workspace_access[0].runs == "read" &&
      tfe_team_project_access.this["saas/platform"].workspace_access[0].variables == "read"
    )
    error_message = "on the secret-bearing saas project the platform team must get custom access with runs = read (no plan)."
  }

  # 3 projects x (platform + viewer) + approvers on the 2 control-plane
  # projects and the saas project + the security team on guardrails = 10.
  assert {
    condition     = length(tfe_team_project_access.this) == 10
    error_message = "3 x (platform + viewer) + 3 approvers + 1 security = 10 project grants."
  }

  # Non-production workload workspaces sharing a project with the control
  # plane get write through a workspace-level grant; control-plane and
  # production workload workspaces never do.
  assert {
    condition     = toset(keys(tfe_team_access.platform_workload)) == toset(["gcp-workload-dev", "aws-workload-dev"]) && alltrue([for g in values(tfe_team_access.platform_workload) : g.access == "write" && g.team_id == "team-platform1"])
    error_message = "only the non-production gcp/aws workload workspaces get a workspace-level platform write grant."
  }

  # Production workloads get the control-plane treatment: the platform team
  # inherits only the custom project grant (plan, variables read-only), so one
  # person cannot set a TF_VAR_* and confirm a prod apply; the approvers team
  # confirms. The tag lets the TFC-layer policy recognise them.
  assert {
    condition = alltrue([
      for ws in ["gcp-workload-prod", "aws-workload-prod"] :
      !contains(keys(tfe_team_access.platform_workload), ws) && contains(module.workspace[ws].tag_names, "tier:production")
    ]) && !contains(module.workspace["gcp-workload-dev"].tag_names, "tier:production")
    error_message = "production workloads must get no workspace-level write grant and must carry the tier:production tag."
  }
}

# A production environment flagged only by is_production (not by its name) is
# protected too, and a non-production one named prod keeps write.
run "production_workloads_follow_is_production" {
  command = plan

  variables {
    environments = {
      live = { is_production = true }
      prod = { is_production = false }
    }
    platform_team_id                = "team-platform1"
    control_plane_approvers_team_id = "team-approvers1"
  }

  # saas applies are confirmed by the control-plane approvers team.
  expect_failures = [check.saas_approvers_dedicated]

  assert {
    condition     = toset(keys(tfe_team_access.platform_workload)) == toset(["gcp-workload-prod", "aws-workload-prod"])
    error_message = "write follows is_production: live (production) gets none, prod (explicitly non-production) keeps it."
  }

  assert {
    condition     = contains(module.workspace["aws-workload-live"].tag_names, "tier:production") && !contains(module.workspace["aws-workload-prod"].tag_names, "tier:production")
    error_message = "tier:production follows is_production."
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

  # saas applies are confirmed by the control-plane approvers team.
  expect_failures = [check.saas_approvers_dedicated]

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
    platform_team_id                = "team-platform1"
    control_plane_approvers_team_id = "team-approvers1"
    security_team_id                = null
  }

  assert {
    condition     = length([for k, g in tfe_team_project_access.this : k if startswith(k, "guardrails/")]) == 0
    error_message = "without security_team_id no team may get access to the guardrails project."
  }

  expect_failures = [check.guardrails_project_has_security_team, check.saas_approvers_dedicated]
}

run "security_team_must_differ_from_platform" {
  command = plan

  variables {
    platform_team_id = "team-same1"
    security_team_id = "team-same1"
  }

  # The check also warns: no approvers team for the saas project.
  expect_failures = [terraform_data.input_contract, check.secret_bearing_projects_have_approvers]
}

run "platform_team_runs_override" {
  command = plan

  variables {
    platform_team_id                 = "team-platform1"
    platform_team_control_plane_runs = "read"
  }

  # No approvers team: only organization owners can confirm runs on the
  # secret-bearing projects, so a check warns.
  expect_failures = [check.secret_bearing_projects_have_approvers]

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

  expect_failures = [terraform_data.input_contract, check.saas_approvers_dedicated]
}

# Opt-in split: workload workspaces move to <prefix><cloud>-workloads projects.
# A workloads project that holds a production workload gets the control-plane
# treatment (custom platform access, approvers confirm), and its
# non-production workloads get write through workspace-level grants.
run "split_workload_projects" {
  command = plan

  variables {
    split_workload_projects         = true
    platform_team_id                = "team-platform1"
    control_plane_approvers_team_id = "team-approvers1"
  }

  # saas applies are confirmed by the control-plane approvers team.
  expect_failures = [check.saas_approvers_dedicated]

  assert {
    condition     = toset(keys(tfe_project.this)) == toset(["gcp", "aws", "saas", "gcp-workloads", "aws-workloads", "guardrails"]) && tfe_project.this["gcp-workloads"].name == "landing-zone-gcp-workloads" && tfe_project.this["aws"].name == "landing-zone-aws"
    error_message = "split mode adds <prefix>gcp-workloads / <prefix>aws-workloads and keeps the control-plane project names."
  }

  assert {
    condition = alltrue([
      for p in ["gcp-workloads", "aws-workloads"] :
      tfe_team_project_access.this["${p}/platform"].access == "custom" &&
      tfe_team_project_access.this["${p}/platform"].workspace_access[0].runs == "plan" &&
      tfe_team_project_access.this["${p}/platform"].workspace_access[0].variables == "read" &&
      tfe_team_project_access.this["${p}/approvers"].workspace_access[0].runs == "apply" &&
      tfe_team_project_access.this["${p}/approvers"].team_id == "team-approvers1"
    ]) && tfe_team_project_access.this["gcp/platform"].access == "custom"
    error_message = "a workloads project holding a production workload gets custom platform access (plan, variables read-only) and an approvers grant."
  }

  assert {
    condition     = toset(keys(tfe_team_access.platform_workload)) == toset(["gcp-workload-dev", "aws-workload-dev"]) && alltrue([for g in values(tfe_team_access.platform_workload) : g.access == "write"])
    error_message = "only the non-production workloads get workspace-level write in a project that holds a production workload."
  }
}

# A workloads project with no production workload keeps fixed platform write
# and needs neither approvers nor workspace-level grants.
run "split_workload_projects_nonprod_only" {
  command = plan

  variables {
    environments = {
      dev     = { is_production = false }
      staging = { is_production = false }
    }
    split_workload_projects         = true
    platform_team_id                = "team-platform1"
    control_plane_approvers_team_id = "team-approvers1"
  }

  # saas applies are confirmed by the control-plane approvers team.
  expect_failures = [check.saas_approvers_dedicated]

  assert {
    condition     = tfe_team_project_access.this["gcp-workloads/platform"].access == "write" && tfe_team_project_access.this["aws-workloads/platform"].access == "write" && !contains(keys(tfe_team_project_access.this), "aws-workloads/approvers") && !contains(keys(tfe_team_project_access.this), "gcp-workloads/approvers")
    error_message = "a non-production-only workloads project keeps fixed platform write and gets no approvers grant."
  }

  assert {
    condition     = length(tfe_team_access.platform_workload) == 0
    error_message = "no workspace-level grants are needed when the workloads project holds no production workload."
  }
}

# A plan is code execution with the workspace's environment. Any workspace that
# holds a static secret (a sensitive workspace_variables entry, such as the
# saas-outputs-reader TFE_TOKEN) is secret-bearing: the platform team gets
# runs = read on its project, the workspace gets no workspace-level write and
# no speculative plans.
run "secret_bearing_production_workload_drops_platform_to_read" {
  command = plan

  variables {
    split_workload_projects         = true
    platform_team_id                = "team-platform1"
    control_plane_approvers_team_id = "team-approvers1"
    workspace_variables = {
      "gcp-workload-prod" = {
        TFE_TOKEN = { value = "not-a-real-token", category = "env", sensitive = true }
      }
    }
  }

  # saas applies are confirmed by the control-plane approvers team.
  expect_failures = [check.saas_approvers_dedicated]

  assert {
    condition     = tfe_team_project_access.this["gcp-workloads/platform"].access == "custom" && tfe_team_project_access.this["gcp-workloads/platform"].workspace_access[0].runs == "read"
    error_message = "a project holding a workspace with a sensitive variable must give the platform team runs = read: a plan there can read the variable."
  }

  assert {
    condition     = tfe_team_project_access.this["aws-workloads/platform"].workspace_access[0].runs == "plan"
    error_message = "a production workloads project without a static secret keeps platform runs = plan."
  }

  assert {
    condition     = contains(keys(tfe_team_access.platform_workload), "gcp-workload-dev") && !contains(keys(tfe_team_access.platform_workload), "gcp-workload-prod")
    error_message = "non-production workloads without a secret keep workspace-level write; a secret-bearing workspace never gets it."
  }

  assert {
    condition     = module.workspace["gcp-workload-prod"].speculative_enabled == false
    error_message = "a secret-bearing workspace must not run speculative plans (a PR plan can read its environment)."
  }

  assert {
    condition     = contains(keys(tfe_team_project_access.this), "gcp-workloads/approvers")
    error_message = "a secret-bearing project must keep a confirmer: the approvers team."
  }
}

# The bridge flag alone marks the workspace: its TFE_TOKEN may be set by hand.
run "saas_bridge_flag_marks_nonprod_workload_secret_bearing" {
  command = plan

  variables {
    environments = {
      dev = { is_production = false }
    }
    split_workload_projects         = true
    platform_team_id                = "team-platform1"
    control_plane_approvers_team_id = "team-approvers1"
    workspace_variables = {
      "aws-workload-dev" = {
        enable_saas_secret_bridge = { value = "true", hcl = true }
      }
    }
  }

  # saas applies are confirmed by the control-plane approvers team.
  expect_failures = [check.saas_approvers_dedicated]

  assert {
    condition     = tfe_team_project_access.this["aws-workloads/platform"].access == "custom" && tfe_team_project_access.this["aws-workloads/platform"].workspace_access[0].runs == "read" && contains(keys(tfe_team_project_access.this), "aws-workloads/approvers")
    error_message = "a non-production bridging workload is secret-bearing: platform runs = read, approvers confirm."
  }

  assert {
    condition     = tfe_team_project_access.this["gcp-workloads/platform"].access == "write"
    error_message = "a non-production workloads project without a secret keeps fixed platform write."
  }

  assert {
    condition     = module.workspace["aws-workload-dev"].speculative_enabled == false && module.workspace["gcp-workload-dev"].speculative_enabled == true
    error_message = "a non-production bridging workload runs no speculative plans; a non-production workload without a secret keeps them."
  }
}

# The committed workspace_variables_file can turn the bridge on as well (a
# YAML bool), and a TF_VAR_ env variable can too.
run "saas_bridge_flag_from_committed_file_or_env" {
  command = plan

  variables {
    split_workload_projects  = true
    platform_team_id         = "team-platform1"
    workspace_variables_file = "tests/fixtures/tfc-workspaces-bridge.yaml"
    workspace_variables = {
      "gcp-workload-dev" = {
        TF_VAR_enable_saas_secret_bridge = { value = "true", category = "env" }
      }
    }
  }

  # No approvers team: only organization owners can confirm runs on the
  # secret-bearing projects, so a check warns.
  expect_failures = [check.secret_bearing_projects_have_approvers]

  assert {
    condition     = module.workspace["aws-workload-dev"].speculative_enabled == false && module.workspace["gcp-workload-dev"].speculative_enabled == false
    error_message = "the bridge flag from the committed file or a TF_VAR_ env variable marks the workspace secret-bearing."
  }

  assert {
    condition     = length(tfe_team_access.platform_workload) == 0
    error_message = "a secret-bearing non-production workload gets no workspace-level platform write."
  }
}

# The bridge flag fails closed: any value other than an explicit false
# ("false", "0", "" after trimming spaces and quotes) counts as on.
run "saas_bridge_flag_fails_closed_on_truthy_values" {
  command = plan

  variables {
    split_workload_projects = true
    platform_team_id        = "team-platform1"
    workspace_variables = {
      "gcp-workload-dev" = {
        enable_saas_secret_bridge = { value = "1" }
      }
      "aws-workload-dev" = {
        enable_saas_secret_bridge = { value = "!false", hcl = true }
      }
    }
  }

  # No approvers team: only organization owners can confirm runs on the
  # secret-bearing projects, so a check warns.
  expect_failures = [check.secret_bearing_projects_have_approvers]

  assert {
    condition     = module.workspace["gcp-workload-dev"].speculative_enabled == false && module.workspace["aws-workload-dev"].speculative_enabled == false
    error_message = "a bridge flag of \"1\" or the HCL expression !false must mark the workspace secret-bearing."
  }

  assert {
    condition     = length(tfe_team_access.platform_workload) == 0
    error_message = "a workspace whose bridge flag is not an explicit false gets no workspace-level platform write."
  }
}

run "saas_bridge_flag_explicit_false_is_off" {
  command = plan

  variables {
    split_workload_projects = true
    platform_team_id        = "team-platform1"
    workspace_variables = {
      "gcp-workload-dev" = {
        enable_saas_secret_bridge = { value = " \"False\" ", hcl = true }
      }
      "aws-workload-dev" = {
        enable_saas_secret_bridge = { value = "false", hcl = true }
      }
    }
  }

  # No approvers team: only organization owners can confirm runs on the
  # secret-bearing projects, so a check warns.
  expect_failures = [check.secret_bearing_projects_have_approvers]

  assert {
    condition     = module.workspace["gcp-workload-dev"].speculative_enabled == true && module.workspace["aws-workload-dev"].speculative_enabled == true
    error_message = "an explicit false bridge flag does not make the workspace secret-bearing."
  }

  assert {
    condition     = contains(keys(tfe_team_access.platform_workload), "gcp-workload-dev") && contains(keys(tfe_team_access.platform_workload), "aws-workload-dev")
    error_message = "a non-production workload with the bridge explicitly off keeps workspace-level platform write."
  }
}

# Without an approvers team, only organization owners can confirm runs on a
# secret-bearing project: a check warns.
run "secret_bearing_without_approvers_warns" {
  command = plan

  variables {
    enable_saas             = false
    saas_workspaces         = []
    split_workload_projects = true
    platform_team_id        = "team-platform1"
    workspace_variables = {
      "gcp-workload-dev" = {
        enable_saas_secret_bridge = { value = "true", hcl = true }
      }
    }
  }

  expect_failures = [check.secret_bearing_projects_have_approvers]
}

# A service-role key is a secret even when it was not marked sensitive.
run "service_role_key_name_marks_workspace" {
  command = plan

  variables {
    split_workload_projects         = true
    platform_team_id                = "team-platform1"
    control_plane_approvers_team_id = "team-approvers1"
    workspace_variables = {
      "aws-workload-dev" = {
        SUPABASE_SERVICE_ROLE_KEY = { value = "not-a-real-key", category = "env" }
      }
      "gcp-workload-dev" = {
        db_passwd = { value = "not-a-real-password" }
      }
    }
  }

  # saas applies are confirmed by the control-plane approvers team.
  expect_failures = [check.saas_approvers_dedicated]

  assert {
    condition     = module.workspace["aws-workload-dev"].speculative_enabled == false && module.workspace["gcp-workload-dev"].speculative_enabled == false
    error_message = "*_SERVICE_ROLE_KEY and *_PASSWD keys mark the workspace secret-bearing."
  }
}

# A token-shaped key is a secret even when it was not marked sensitive.
run "secret_named_variable_marks_workspace" {
  command = plan

  variables {
    split_workload_projects = true
    platform_team_id        = "team-platform1"
    workspace_variables = {
      "gcp-workload-dev" = {
        VERCEL_API_TOKEN = { value = "not-a-real-token", category = "env" }
      }
    }
  }

  # No approvers team: only organization owners can confirm runs on the
  # secret-bearing projects, so a check warns.
  expect_failures = [check.secret_bearing_projects_have_approvers]

  assert {
    condition     = module.workspace["gcp-workload-dev"].speculative_enabled == false && !contains(keys(tfe_team_access.platform_workload), "gcp-workload-dev")
    error_message = "a workspace with a token-shaped variable key is secret-bearing even when sensitive = false."
  }
}

# A sensitive value in the shared variable set reaches every workspace except
# gcp-guardrails, so every shared project is secret-bearing.
run "sensitive_common_variable_marks_every_workspace" {
  command = plan

  variables {
    split_workload_projects = true
    platform_team_id        = "team-platform1"
    common_workspace_variables = {
      some_api_key = { value = "not-a-real-key", category = "terraform", sensitive = true }
    }
  }

  expect_failures = [check.secret_bearing_control_plane_project, check.secret_bearing_projects_have_approvers]

  assert {
    condition = alltrue([
      for k, g in tfe_team_project_access.this : g.access == "custom" && g.workspace_access[0].runs == "read"
      if g.team_id == "team-platform1"
    ]) && length([for k, g in tfe_team_project_access.this : k if g.team_id == "team-platform1"]) == 5
    error_message = "a sensitive common variable makes every shared project secret-bearing: platform runs = read on all five."
  }

  assert {
    condition     = module.workspace["gcp-workload-dev"].speculative_enabled == false && module.workspace["aws-workload-dev"].speculative_enabled == false
    error_message = "a sensitive common variable turns off speculative plans on every workspace."
  }
}

run "secret_bearing_speculative_opt_out" {
  command = plan

  variables {
    split_workload_projects              = true
    platform_team_id                     = "team-platform1"
    enable_speculative_on_secret_bearing = true
    disable_speculative_on_production    = false
    workspace_variables = {
      "gcp-workload-prod" = {
        TFE_TOKEN = { value = "not-a-real-token", category = "env", sensitive = true }
      }
    }
  }

  # No approvers team: only organization owners can confirm runs on the
  # secret-bearing projects, so a check warns.
  expect_failures = [check.secret_bearing_projects_have_approvers]

  assert {
    condition     = module.workspace["gcp-workload-prod"].speculative_enabled == true
    error_message = "enable_speculative_on_secret_bearing = true keeps speculative plans on secret-bearing workspaces."
  }

  assert {
    condition     = tfe_team_project_access.this["gcp-workloads/platform"].workspace_access[0].runs == "read"
    error_message = "the opt-out covers speculative plans only: the platform team stays at runs = read."
  }
}

# tfc-admin holds the org-admin TFE_TOKEN: it stays off speculative plans even
# when an override list leaves it out.
run "tfc_admin_speculative_off_without_list_entry" {
  command = plan

  variables {
    manage_tfc_admin_workspace      = true
    import_tfc_admin_workspace      = false
    speculative_disabled_workspaces = []
  }

  assert {
    condition     = module.workspace["tfc-admin"].speculative_enabled == false && module.workspace["gcp-organization"].speculative_enabled == true
    error_message = "the self-managed tfc-admin workspace is secret-bearing: no speculative plans even when speculative_disabled_workspaces omits it."
  }
}

# One project per cloud: a secret-bearing production workload drags the control
# plane to runs = read. A check recommends split_workload_projects.
run "secret_bearing_in_control_plane_project_warns" {
  command = plan

  variables {
    split_workload_projects = false
    platform_team_id        = "team-platform1"
    workspace_variables = {
      "gcp-workload-prod" = {
        TFE_TOKEN = { value = "not-a-real-token", category = "env", sensitive = true }
      }
    }
  }

  expect_failures = [check.secret_bearing_control_plane_project, check.secret_bearing_projects_have_approvers]

  assert {
    condition     = tfe_team_project_access.this["gcp/platform"].workspace_access[0].runs == "read" && !contains(keys(tfe_team_access.platform_workload), "gcp-workload-prod")
    error_message = "with one project per cloud, a secret-bearing workload puts the whole project at platform runs = read."
  }
}

# The state export team reads state versions on every project except the
# security-only guardrails project, and nothing else.
run "state_backup_team_reads_state_only" {
  command = plan

  variables {
    platform_team_id     = "team-platform1"
    state_backup_team_id = "team-backup1"
  }

  # No approvers team: only organization owners can confirm runs on the
  # secret-bearing projects, so a check warns.
  expect_failures = [check.secret_bearing_projects_have_approvers]

  assert {
    condition = toset([for k, g in tfe_team_project_access.this : split("/", k)[0] if g.team_id == "team-backup1"]) == toset(["gcp", "aws"]) && alltrue([
      for k, g in tfe_team_project_access.this : (
        g.access == "custom" &&
        g.workspace_access[0].state_versions == "read" &&
        g.workspace_access[0].runs == "read" &&
        g.workspace_access[0].variables == "none" &&
        g.workspace_access[0].locking == false &&
        g.project_access[0].teams == "none"
      ) if g.team_id == "team-backup1"
    ])
    error_message = "the state backup team must get custom state_versions = read (runs read, variables none) on every project but guardrails and saas."
  }
}

run "state_backup_team_must_be_dedicated" {
  command = plan

  variables {
    platform_team_id     = "team-same1"
    state_backup_team_id = "team-same1"
  }

  expect_failures = [terraform_data.input_contract, check.secret_bearing_projects_have_approvers]
}

# The drift team (TFC_TOKEN_DRIFT) queues refresh-only plans. A plan can read
# the workspace's variables, so it never gets a secret-bearing project: saas
# (always), the tfc-admin project, and here gcp-workloads (TFE_TOKEN on
# gcp-workload-prod).
run "drift_team_plans_only_outside_secret_bearing_projects" {
  command = plan

  variables {
    split_workload_projects = true
    platform_team_id        = "team-platform1"
    drift_team_id           = "team-drift1"
    workspace_variables = {
      "gcp-workload-prod" = {
        TFE_TOKEN = { value = "not-a-real-token", category = "env", sensitive = true }
      }
    }
  }

  # No approvers team: only organization owners can confirm runs on the
  # secret-bearing projects, so a check warns.
  expect_failures = [check.secret_bearing_projects_have_approvers]

  assert {
    condition = (
      toset([for k, g in tfe_team_project_access.this : split("/", k)[0] if g.team_id == "team-drift1"]) == toset(["gcp", "aws", "aws-workloads"]) &&
      alltrue([for k, g in tfe_team_project_access.this : (
        g.access == "custom" &&
        g.workspace_access[0].runs == "plan" && g.workspace_access[0].variables == "none" &&
        g.workspace_access[0].state_versions == "read" && g.workspace_access[0].locking == false &&
        g.project_access[0].teams == "none"
      ) if g.team_id == "team-drift1"])
    )
    error_message = "the drift team gets runs = plan, state read, no variables, and never a secret-bearing project (saas, gcp-workloads with the token)."
  }

  assert {
    condition = (
      contains(output.drift_workspaces, "gcp-organization") &&
      contains(output.drift_workspaces, "aws-workload-prod") &&
      !contains(output.drift_workspaces, "gcp-workload-prod") &&
      !contains(output.drift_workspaces, "gcp-workload-dev") &&
      !contains(output.drift_workspaces, "saas-web") &&
      !contains(output.drift_workspaces, "gcp-guardrails")
    )
    error_message = "drift_workspaces must list exactly the workspaces in the projects the drift team may plan."
  }
}

# Without the variable there is no grant and nothing to list.
run "drift_team_unset_grants_nothing" {
  command = plan

  variables {
    platform_team_id = "team-platform1"
  }

  expect_failures = [check.secret_bearing_projects_have_approvers]

  assert {
    condition     = length([for k in keys(tfe_team_project_access.this) : k if endswith(k, "/drift")]) == 0 && length(output.drift_workspaces) == 0
    error_message = "drift_team_id = null must create no drift grant."
  }
}

run "drift_team_must_be_dedicated" {
  command = plan

  variables {
    platform_team_id = "team-same1"
    drift_team_id    = "team-same1"
  }

  expect_failures = [terraform_data.input_contract, check.secret_bearing_projects_have_approvers]
}

# gcp-guardrails release tags (terraform-apply.yml, TFC_TOKEN_GUARDRAILS): a
# dedicated team reads runs on the guardrails project and nothing else.
run "guardrails_release_reader_gets_read_runs_only" {
  command = plan

  variables {
    guardrails_release_reader_team_id = "team-guardrelease1"
  }

  assert {
    condition     = tfe_team_project_access.this["guardrails/release-reader"].access == "custom" && tfe_team_project_access.this["guardrails/release-reader"].workspace_access[0].runs == "read" && tfe_team_project_access.this["guardrails/release-reader"].workspace_access[0].state_versions == "none" && tfe_team_project_access.this["guardrails/release-reader"].workspace_access[0].variables == "none"
    error_message = "The guardrails release reader may read runs and nothing else."
  }

  assert {
    condition     = tfe_team_project_access.this["guardrails/release-reader"].workspace_access[0].locking == false && tfe_team_project_access.this["guardrails/release-reader"].project_access[0].teams == "none" && tfe_team_project_access.this["guardrails/release-reader"].workspace_access[0].policy_overrides == false
    error_message = "The guardrails release reader must not lock workspaces, manage teams or override policies."
  }

  assert {
    condition     = jsonencode([for k, g in tfe_team_project_access.this : k if g.team_id == "team-guardrelease1"]) == jsonencode(["guardrails/release-reader"]) && contains(keys(tfe_team_project_access.this), "guardrails/security")
    error_message = "The release reader gets one grant, on the guardrails project, and the security team keeps its own."
  }
}

run "guardrails_release_reader_null_creates_no_grant" {
  command = plan

  assert {
    condition     = !contains(keys(tfe_team_project_access.this), "guardrails/release-reader")
    error_message = "guardrails_release_reader_team_id = null must create no release-reader grant."
  }
}

run "guardrails_release_reader_must_be_dedicated" {
  command = plan

  variables {
    guardrails_release_reader_team_id = "team-security1"
  }

  expect_failures = [terraform_data.input_contract]
}

run "guardrails_release_reader_must_not_be_the_drift_team" {
  command = plan

  variables {
    guardrails_release_reader_team_id = "team-same1"
    drift_team_id                     = "team-same1"
  }

  expect_failures = [terraform_data.input_contract]
}

run "guardrails_release_reader_id_is_validated" {
  command = plan

  variables {
    guardrails_release_reader_team_id = "not-a-team"
  }

  expect_failures = [var.guardrails_release_reader_team_id]
}

# TFC applies with the exact version CI tests. The default itself must equal
# .tool-versions (scripts/check-consistency.sh), so this test does not repeat the
# number and a Renovate toolchain bump does not need to edit it.
run "terraform_version_is_exact" {
  command = plan

  assert {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.terraform_version)) && alltrue([for ws in output.workspace_names : module.workspace[ws].terraform_version == var.terraform_version])
    error_message = "the terraform_version default must be an exact release and every workspace must run it (the version CI pins in .tool-versions)."
  }
}

run "terraform_version_constraint_rejected" {
  command = plan

  variables {
    terraform_version = "~> 1.17"
  }

  expect_failures = [var.terraform_version]
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

# A hand-created (unmanaged) tfc-admin workspace is looked up and attached
# too, so the TFC-layer guard judges tfc-admin's own plans.
run "policy_sets_judge_unmanaged_tfc_admin" {
  command = plan

  variables {
    enable_policy_sets = true
    vcs_repo           = { identifier = "acme/landing-zone", oauth_token_id = "ot-abc123" }
  }

  assert {
    condition     = length(data.tfe_workspace.tfc_admin) == 1 && length(local.policy_set_workspace_ids) == length(module.workspace) + 1
    error_message = "with policy sets on, the unmanaged tfc-admin workspace must be attached to both sets as well as every managed workspace."
  }

  # vcs_repo without self-management still warns about speculative plans.
  expect_failures = [check.tfc_admin_workspace_hardened]
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
    condition     = module.workspace["tfc-admin"].speculative_enabled == false && toset(module.workspace["tfc-admin"].trigger_patterns) == toset(["envs/tfc-admin/**", "modules/tfc/workspace/**", "config/landing-zone.yaml"])
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

  # saas applies are confirmed by the control-plane approvers team.
  expect_failures = [check.saas_approvers_dedicated]

  assert {
    condition     = module.workspace["tfc-admin"].auto_apply == false && module.workspace["tfc-admin"].auto_apply_run_trigger == false && module.workspace["tfc-admin"].speculative_enabled == false
    error_message = "tfc-admin must never auto-apply and must not run speculative plans."
  }

  assert {
    condition     = tfe_team_access.tfc_admin[0].team_id == "team-tfcadmin1" && tfe_team_access.tfc_admin[0].access == "write"
    error_message = "the tfc-admin team gets explicit write (apply) on the tfc-admin workspace."
  }

  assert {
    condition     = !contains(keys(tfe_team_project_access.this), "platform/approvers") && tfe_team_project_access.this["platform/platform"].workspace_access[0].runs == "read"
    error_message = "on the platform project (tfc-admin only, holds TFE_TOKEN) the approvers team gets no grant and the platform team gets runs = read: a plan there could read the org-admin token."
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

# ── New environment = one PR + shared-workspace confirmations ───────────────
# tfc-admin derives a new environment's workload SA emails from org.prefix
# (gcp_project_prefix) and the static gcp-bootstrap outputs, so the new
# gcp-workload-<env> gets its TFC_GCP_* env vars in the same tfc-admin apply
# that creates it (no second tfc-admin pass).
run "sa_emails_derived_from_prefix_and_bootstrap_outputs" {
  command = plan

  variables {
    gcp_bootstrap_outputs_from_tfc = true
    gcp_project_prefix             = "acme"
    workspace_execution_modes      = {}
  }

  override_data {
    target = data.tfe_outputs.gcp_bootstrap[0]
    values = {
      nonsensitive_values = {
        contract = {
          admin_project_id           = "acme-admin-1a2b"
          tfc_workload_provider_name = "projects/123456789/locations/global/workloadIdentityPools/tfc-pool/providers/tfc-provider"
          # Phase-0 outputs: only the control plane + dev existed when gcp-bootstrap last applied.
          tfc_plan_service_accounts  = { "gcp-projects" = "acme-projects-plan@acme-admin-1a2b.iam.gserviceaccount.com", "gcp-workload-dev" = "acme-wl-dev-plan@acme-admin-1a2b.iam.gserviceaccount.com" }
          tfc_apply_service_accounts = { "gcp-projects" = "acme-projects-apply@acme-admin-1a2b.iam.gserviceaccount.com", "gcp-workload-dev" = "acme-wl-dev-apply@acme-admin-1a2b.iam.gserviceaccount.com" }
        }
      }
    }
  }

  override_data {
    target = data.tfe_workspace.tfc_admin[0]
    values = { id = "ws-tfcadmin" }
  }

  # gcp-workload-prod is not in the bootstrap outputs yet: its emails are derived.
  assert {
    condition = (
      module.workspace["gcp-workload-prod"].variable_values["TFC_GCP_PLAN_SERVICE_ACCOUNT_EMAIL"] == "acme-wl-prod-plan@acme-admin-1a2b.iam.gserviceaccount.com" &&
      module.workspace["gcp-workload-prod"].variable_values["TFC_GCP_APPLY_SERVICE_ACCOUNT_EMAIL"] == "acme-wl-prod-apply@acme-admin-1a2b.iam.gserviceaccount.com" &&
      module.workspace["gcp-workload-prod"].variable_values["TFC_GCP_WORKLOAD_PROVIDER_NAME"] == "projects/123456789/locations/global/workloadIdentityPools/tfc-pool/providers/tfc-provider"
    )
    error_message = "a new gcp-workload-<env> must get <prefix>-wl-<env>-{plan,apply}@<admin_project_id>.iam.gserviceaccount.com and the bootstrap WIF provider in the same apply."
  }

  assert {
    condition     = contains(output.dynamic_credential_workspaces.gcp, "gcp-workload-dev") && contains(output.dynamic_credential_workspaces.gcp, "gcp-workload-prod") && contains(output.dynamic_credential_workspaces.gcp, "gcp-projects")
    error_message = "derived workload emails merge with the bootstrap outputs, never replace them."
  }

  # Only workload SAs are derived; control-plane SAs come from the outputs.
  assert {
    condition     = toset(keys(local.derived_gcp_plan_sas)) == toset(["gcp-workload-dev", "gcp-workload-prod"])
    error_message = "tfc-admin derives the per-environment workload SAs only."
  }
}

# No derivation without the prefix or the bootstrap outputs.
run "sa_emails_not_derived_without_inputs" {
  command = plan

  assert {
    condition     = length(local.derived_gcp_plan_sas) == 0 && length(output.dynamic_credential_workspaces.gcp) == 0
    error_message = "without gcp_bootstrap_outputs_from_tfc and a prefix, nothing is derived (greenfield phase 0 is unchanged)."
  }
}

# The derived email must match what gcp-bootstrap actually created.
run "derived_email_check_matches_bootstrap_output" {
  command = plan

  variables {
    gcp_bootstrap_outputs_from_tfc = true
    gcp_project_prefix             = "acme"
    workspace_execution_modes      = {}
  }

  override_data {
    target = data.tfe_outputs.gcp_bootstrap[0]
    values = {
      nonsensitive_values = {
        contract = {
          admin_project_id           = "acme-admin-1a2b"
          tfc_workload_provider_name = "projects/123456789/locations/global/workloadIdentityPools/tfc-pool/providers/tfc-provider"
          tfc_plan_service_accounts  = { "gcp-workload-dev" = "other-wl-dev-plan@acme-admin-1a2b.iam.gserviceaccount.com" }
          tfc_apply_service_accounts = { "gcp-workload-dev" = "acme-wl-dev-apply@acme-admin-1a2b.iam.gserviceaccount.com" }
        }
      }
    }
  }

  override_data {
    target = data.tfe_workspace.tfc_admin[0]
    values = { id = "ws-tfcadmin" }
  }

  expect_failures = [check.derived_gcp_service_accounts_match_bootstrap]
}

# GCP SA account IDs are at most 30 characters: <prefix>-wl-<env>-apply must fit.
run "derived_account_id_too_long_fails" {
  command = plan

  variables {
    gcp_project_prefix = "acmecorp"
    environments = {
      dev                  = { is_production = false }
      integration-testing2 = { is_production = false }
    }
  }

  expect_failures = [terraform_data.input_contract]
}

# tfc-admin is the DAG root: its apply queues gcp-bootstrap and aws-organization.
run "tfc_admin_triggers_dag_roots" {
  command = plan

  variables {
    # Post-handover: gcp-bootstrap runs remotely.
    workspace_execution_modes = {}
  }

  override_data {
    target = data.tfe_workspace.tfc_admin[0]
    values = { id = "ws-tfcadmin" }
  }

  assert {
    condition     = contains(output.run_triggers, "tfc-admin->gcp-bootstrap") && contains(output.run_triggers, "tfc-admin->aws-organization")
    error_message = "tfc-admin must trigger gcp-bootstrap and aws-organization."
  }

  assert {
    condition     = tfe_run_trigger.dag["tfc-admin->gcp-bootstrap"].sourceable_id == "ws-tfcadmin"
    error_message = "an unmanaged tfc-admin is the trigger source through data.tfe_workspace.tfc_admin."
  }

  # tfc-admin is never a trigger target, and no other DAG root edge is added.
  assert {
    condition     = length([for t in output.run_triggers : t if startswith(t, "tfc-admin->")]) == 2 && length([for t in output.run_triggers : t if endswith(t, "->tfc-admin")]) == 0
    error_message = "tfc-admin triggers exactly the two DAG roots and is never triggered."
  }
}

# While gcp-bootstrap runs locally (phase 0) it is no trigger target.
run "tfc_admin_skips_local_gcp_bootstrap" {
  command = plan

  override_data {
    target = data.tfe_workspace.tfc_admin[0]
    values = { id = "ws-tfcadmin" }
  }

  assert {
    condition     = !contains(output.run_triggers, "tfc-admin->gcp-bootstrap") && contains(output.run_triggers, "tfc-admin->aws-organization")
    error_message = "a local-execution gcp-bootstrap cannot run a triggered run, so tfc-admin must not target it."
  }
}

# Non-prod workloads (is_production explicitly false): queued at creation, and
# run-trigger runs apply.
run "new_nonprod_workload_queues_all_runs_and_auto_applies_triggers" {
  command = plan

  variables {
    enable_nonprod_workload_auto_apply = true
    environments = {
      dev  = { is_production = false }
      prod = { is_production = true }
    }
  }

  assert {
    condition = alltrue([
      for ws in ["gcp-workload-dev", "aws-workload-dev"] :
      module.workspace[ws].queue_all_runs && module.workspace[ws].auto_apply_run_trigger && !module.workspace[ws].auto_apply
    ])
    error_message = "non-prod workloads must queue_all_runs and auto-apply run-trigger runs (merges to the workload itself still need confirmation)."
  }
}

# Only is_production = false opts a workload into auto-apply, whatever its
# name: production environments (even one named dev) never auto-apply, even
# with auto-apply forced on.
run "production_flag_never_auto_applies" {
  command = plan

  variables {
    enable_nonprod_workload_auto_apply = true
    environments = {
      dev     = { is_production = true }
      prd     = { is_production = true }
      prod-eu = { is_production = true }
    }
  }

  assert {
    condition = alltrue([
      for ws in output.workspace_names : !module.workspace[ws].queue_all_runs && !module.workspace[ws].auto_apply_run_trigger
    ])
    error_message = "only is_production = false opts a workload into auto-apply; a production environment must keep manual confirmation."
  }
}

# The default (null) follows the policy sets: off while destroy_guard is not
# attached, on once it is.
run "nonprod_workload_auto_apply_default_off_without_policy_sets" {
  command = plan

  variables {
    environments = {
      dev  = { is_production = false }
      prod = { is_production = true }
    }
  }

  assert {
    condition = alltrue([
      for ws in output.workspace_names : !module.workspace[ws].queue_all_runs && !module.workspace[ws].auto_apply_run_trigger
    ])
    error_message = "without policy sets (no destroy_guard) the default must keep manual confirmation everywhere."
  }
}

run "nonprod_workload_auto_apply_default_on_with_policy_sets" {
  command = plan

  variables {
    enable_policy_sets         = true
    vcs_repo                   = { identifier = "acme/landing-zone", oauth_token_id = "ot-abc123" }
    manage_tfc_admin_workspace = true
    import_tfc_admin_workspace = false
    environments = {
      dev  = { is_production = false }
      prod = { is_production = true }
    }
  }

  assert {
    condition = alltrue([
      for ws in ["gcp-workload-dev", "aws-workload-dev"] :
      module.workspace[ws].queue_all_runs && module.workspace[ws].auto_apply_run_trigger
    ])
    error_message = "with the policy sets (and destroy_guard) attached, the default auto-applies explicit non-prod workloads."
  }

  assert {
    condition     = !module.workspace["gcp-workload-prod"].auto_apply_run_trigger && !module.workspace["aws-workload-prod"].auto_apply_run_trigger
    error_message = "production workloads keep manual confirmation."
  }
}

run "nonprod_workload_auto_apply_opt_out" {
  command = plan

  variables {
    enable_nonprod_workload_auto_apply = false
    environments = {
      dev  = { is_production = false }
      prod = { is_production = true }
    }
  }

  assert {
    condition = alltrue([
      for ws in output.workspace_names : !module.workspace[ws].queue_all_runs && !module.workspace[ws].auto_apply_run_trigger
    ])
    error_message = "enable_nonprod_workload_auto_apply = false restores manual confirmation everywhere."
  }
}

# Production workloads and every shared workspace keep manual confirmation.
run "prod_and_shared_need_confirmation" {
  command = plan

  variables {
    environments = {
      dev  = { is_production = false }
      prod = { is_production = true }
    }
  }

  assert {
    condition = alltrue([
      for ws in output.workspace_names :
      !module.workspace[ws].queue_all_runs && !module.workspace[ws].auto_apply_run_trigger && !module.workspace[ws].auto_apply
      if !contains(["gcp-workload-dev", "aws-workload-dev"], ws)
    ])
    error_message = "production workloads, the control plane, saas, gcp-guardrails and tfc-admin must wait for confirmation."
  }
}

# Once gcp-bootstrap's outputs are read (post-handover), gcp-bootstrap must run
# remotely, or tfc-admin's run trigger has nothing to queue.
run "gcp_bootstrap_local_after_handover_warns" {
  command = plan

  variables {
    gcp_bootstrap_outputs_from_tfc = true
  }

  override_data {
    target = data.tfe_outputs.gcp_bootstrap[0]
    values = { nonsensitive_values = {
      tfc_workload_provider_name = null
      tfc_plan_service_accounts  = {}
      tfc_apply_service_accounts = {}
    } }
  }

  override_data {
    target = data.tfe_workspace.tfc_admin[0]
    values = { id = "ws-tfcadmin" }
  }

  expect_failures = [check.gcp_bootstrap_remote_after_handover]
}

# The effective prefix is validated, including one read from org.prefix.
run "effective_prefix_format_validated" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-bad-prefix.yaml"
    tfc_organization         = "acme"
  }

  expect_failures = [terraform_data.input_contract]
}

# SaaS bridge readers: one hand-created team per saas-<name> workspace, whose
# token (TFE_TOKEN on the workloads bridging that stack only) reads that
# workspace's outputs and nothing else. tfc-admin grants the access; it never
# creates the token.
run "saas_outputs_reader_default_off" {
  command = plan

  assert {
    condition     = length(tfe_team_access.saas_outputs_reader) == 0
    error_message = "without saas_outputs_reader_team_ids no saas outputs-reader grant may exist."
  }
}

run "saas_outputs_reader_one_team_per_stack" {
  command = plan

  variables {
    saas_workspaces = ["web", "admin"]
    saas_outputs_reader_team_ids = {
      "saas-web"   = "team-saasweb1"
      "saas-admin" = "team-saasadmin1"
    }
  }

  assert {
    condition = (
      toset(keys(tfe_team_access.saas_outputs_reader)) == toset(["saas-web", "saas-admin"]) &&
      tfe_team_access.saas_outputs_reader["saas-web"].team_id == "team-saasweb1" &&
      tfe_team_access.saas_outputs_reader["saas-admin"].team_id == "team-saasadmin1"
    )
    error_message = "each outputs-reader team gets a grant on its own saas-* workspace only."
  }

  assert {
    condition = alltrue([
      for k, a in tfe_team_access.saas_outputs_reader :
      a.permissions[0].state_versions == "read-outputs" &&
      a.permissions[0].runs == "read" &&
      a.permissions[0].variables == "none" &&
      a.permissions[0].sentinel_mocks == "none" &&
      !a.permissions[0].workspace_locking &&
      !a.permissions[0].run_tasks
    ])
    error_message = "the outputs-reader grant is custom read-outputs: no state download, no variables, no runs beyond read, no locking or run tasks."
  }

  assert {
    condition     = length([for k, g in tfe_team_project_access.this : k if contains(["team-saasweb1", "team-saasadmin1"], g.team_id)]) == 0
    error_message = "the outputs-reader teams must get no project-level grant."
  }
}

run "saas_outputs_reader_shared_team_rejected" {
  command = plan

  variables {
    saas_workspaces = ["web", "admin"]
    saas_outputs_reader_team_ids = {
      "saas-web"   = "team-saasreader1"
      "saas-admin" = "team-saasreader1"
    }
  }

  expect_failures = [terraform_data.input_contract]
}

run "saas_outputs_reader_unknown_workspace_rejected" {
  command = plan

  variables {
    enable_saas                  = false
    saas_outputs_reader_team_ids = { "saas-web" = "team-saasreader1" }
  }

  expect_failures = [terraform_data.input_contract]
}

run "saas_outputs_reader_must_be_dedicated" {
  command = plan

  variables {
    platform_team_id             = "team-same1"
    saas_outputs_reader_team_ids = { "saas-web" = "team-same1" }
  }

  expect_failures = [terraform_data.input_contract, check.secret_bearing_projects_have_approvers]
}

run "saas_outputs_reader_team_id_format" {
  command = plan

  variables {
    saas_outputs_reader_team_ids = { "saas-web" = "saas-reader" }
  }

  expect_failures = [var.saas_outputs_reader_team_ids]
}

run "saas_outputs_reader_single_team_input_removed" {
  command = plan

  variables {
    saas_outputs_reader_team_id = "team-saasreader1"
  }

  expect_failures = [var.saas_outputs_reader_team_id]
}

# Production is the is_production flag alone: an explicit environment without
# it fails the plan, and the key prod does not make a workload production.
run "explicit_environment_without_is_production_fails" {
  command = plan
  variables {
    environments = { prod = {} }
  }
  expect_failures = [var.environments]
}

run "prod_key_without_flag_is_not_production_by_name" {
  command = plan
  variables {
    environments = { prod = { is_production = false } }
  }
  assert {
    condition     = !contains(local.production_workloads, "gcp-workload-prod")
    error_message = "Only is_production decides production; the key prod alone must not."
  }
}

# SEC-7: saas-* state holds the Supabase database password and service-role
# key. Viewers keep run and variable-name visibility there, but no state and no
# outputs (fixed read includes the full state file).
run "viewers_cannot_download_saas_state" {
  command = plan

  variables {
    viewer_team_ids = ["team-viewer1"]
  }

  assert {
    condition = (
      tfe_team_project_access.this["saas/team-viewer1"].access == "custom" &&
      tfe_team_project_access.this["saas/team-viewer1"].workspace_access[0].state_versions == "none" &&
      tfe_team_project_access.this["saas/team-viewer1"].workspace_access[0].runs == "read" &&
      tfe_team_project_access.this["saas/team-viewer1"].workspace_access[0].variables == "read" &&
      tfe_team_project_access.this["saas/team-viewer1"].workspace_access[0].locking == false &&
      tfe_team_project_access.this["saas/team-viewer1"].project_access[0].teams == "none"
    )
    error_message = "viewers must not read saas state (it holds the Supabase database password and service-role key); read-outputs would expose them too."
  }

  assert {
    condition     = tfe_team_project_access.this["gcp/team-viewer1"].access == "read" && tfe_team_project_access.this["aws/team-viewer1"].access == "read"
    error_message = "viewers keep fixed read on projects without secrets in state."
  }
}

run "saas_state_backup_opt_in" {
  command = plan

  variables {
    platform_team_id         = "team-platform1"
    state_backup_team_id     = "team-backup1"
    enable_saas_state_backup = true
  }

  expect_failures = [check.secret_bearing_projects_have_approvers]

  assert {
    condition = (
      tfe_team_project_access.this["saas/state-backup"].team_id == "team-backup1" &&
      tfe_team_project_access.this["saas/state-backup"].workspace_access[0].state_versions == "read" &&
      tfe_team_project_access.this["saas/state-backup"].workspace_access[0].variables == "none"
    )
    error_message = "enable_saas_state_backup = true grants the backup team state read on saas."
  }
}

run "dedicated_saas_approvers" {
  command = plan

  variables {
    platform_team_id                = "team-platform1"
    control_plane_approvers_team_id = "team-approvers1"
    saas_approvers_team_id          = "team-saasapprove1"
  }

  assert {
    condition = (
      !contains(keys(tfe_team_project_access.this), "saas/approvers") &&
      tfe_team_project_access.this["saas/saas-approvers"].team_id == "team-saasapprove1" &&
      tfe_team_project_access.this["saas/saas-approvers"].access == "custom" &&
      tfe_team_project_access.this["saas/saas-approvers"].workspace_access[0].runs == "apply" &&
      tfe_team_project_access.this["gcp/approvers"].team_id == "team-approvers1" &&
      tfe_team_project_access.this["aws/approvers"].team_id == "team-approvers1" &&
      !contains(keys(tfe_team_project_access.this), "gcp/saas-approvers")
    )
    error_message = "with saas_approvers_team_id set, only that team confirms saas applies; the control-plane approvers keep the other projects."
  }
}

run "saas_approvers_must_be_dedicated" {
  command = plan

  variables {
    platform_team_id       = "team-platform1"
    saas_approvers_team_id = "team-platform1"
  }

  expect_failures = [terraform_data.input_contract]
}

run "saas_approvers_differ_from_control_plane_approvers" {
  command = plan

  variables {
    platform_team_id                = "team-platform1"
    control_plane_approvers_team_id = "team-approvers1"
    saas_approvers_team_id          = "team-approvers1"
  }

  expect_failures = [terraform_data.input_contract]
}

run "saas_without_dedicated_approvers_warns" {
  command = plan

  variables {
    control_plane_approvers_team_id = "team-approvers1"
  }

  expect_failures = [check.saas_approvers_dedicated]
}

# SEC-7: the platform team keeps runs and variables read on saas, but no state
# and no outputs: read-outputs can still return a sensitive output (the
# Supabase database password, the service-role key) through the API. Bridging
# workloads read those outputs with their saas-outputs-reader team token.
run "platform_cannot_read_saas_outputs" {
  command = plan

  variables {
    platform_team_id                = "team-platform1"
    control_plane_approvers_team_id = "team-approvers1"
    saas_approvers_team_id          = "team-saasapprove1"
  }

  assert {
    condition = (
      tfe_team_project_access.this["saas/platform"].access == "custom" &&
      tfe_team_project_access.this["saas/platform"].workspace_access[0].state_versions == "none" &&
      tfe_team_project_access.this["saas/platform"].workspace_access[0].runs == "read" &&
      tfe_team_project_access.this["saas/platform"].workspace_access[0].variables == "read"
    )
    error_message = "the platform team must not read saas state or outputs (state_versions = none); runs and variables stay read."
  }

  assert {
    condition = alltrue([
      for p in ["gcp", "aws"] : tfe_team_project_access.this["${p}/platform"].workspace_access[0].state_versions == "read-outputs"
    ])
    error_message = "the platform team keeps read-outputs on projects without secrets in state."
  }
}

# An upstream whose contract lost a credential key (a rename, or an apply that
# has not happened yet) must stop the plan instead of dropping the TFC_*
# dynamic-credential variables of every workspace it feeds.
run "gcp_bootstrap_contract_missing_keys_fails" {
  command = plan

  variables {
    gcp_bootstrap_outputs_from_tfc = true
    workspace_execution_modes      = {}
  }

  override_data {
    target = data.tfe_outputs.gcp_bootstrap[0]
    values = { nonsensitive_values = { contract = { admin_project_id = "admin-proj" } } }
  }

  override_data {
    target = data.tfe_workspace.tfc_admin[0]
    values = { id = "ws-tfcadmin" }
  }

  expect_failures = [data.tfe_outputs.gcp_bootstrap]
}

run "aws_organization_contract_missing_keys_fails" {
  command = plan

  variables {
    aws_organization_outputs_from_tfc = true
  }

  override_data {
    target = data.tfe_outputs.aws_organization[0]
    values = { nonsensitive_values = { contract = { tfc_plan_role_arns = {} } } }
  }

  override_data {
    target = data.tfe_workspace.tfc_admin[0]
    values = { id = "ws-tfcadmin" }
  }

  expect_failures = [data.tfe_outputs.aws_organization]
}
