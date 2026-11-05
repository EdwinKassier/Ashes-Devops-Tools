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
  enable_aws      = true
  enable_saas     = true
  saas_workspaces = ["web"]
}

run "declares_every_workspace" {
  command = plan

  # 4 GCP control plane + 2 gcp-workload + 6 AWS control plane + 2 aws-workload +
  # 1 saas = 15.
  assert {
    condition     = length(output.workspace_names) == 15
    error_message = "tfc-admin must declare a workspace for each root, each per-env workload, and each saas entry."
  }

  assert {
    condition = alltrue([
      for k in ["gcp-bootstrap", "gcp-organization", "gcp-projects", "gcp-network-hub",
      "gcp-workload-dev", "gcp-workload-prod", "aws-security", "aws-workload-prod", "saas-web"] :
      contains(output.workspace_names, k)
    ])
    error_message = "control-plane, per-env workload, and saas workspaces must all be declared."
  }

  # One project per cloud in use; no platform project unless tfc-admin is self-managed.
  assert {
    condition     = toset(keys(tfe_project.this)) == toset(["gcp", "aws", "saas"])
    error_message = "one TFC project per enabled cloud must be created."
  }
}

run "gcp_only_by_default" {
  command = plan

  variables {
    enable_aws      = false
    enable_saas     = false
    saas_workspaces = []
  }

  # 4 GCP control plane + 2 gcp-workload = 6; no AWS workspaces.
  assert {
    condition     = length(output.workspace_names) == 6 && !contains(output.workspace_names, "aws-organization")
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

# Module-only PRs must trigger plans: each workspace watches its own dir plus
# the module domains its root consumes.
run "trigger_patterns_cover_module_domains" {
  command = plan

  assert {
    condition     = module.workspace["gcp-organization"].trigger_patterns == tolist(["envs/gcp/organization/**", "modules/gcp/**"])
    error_message = "GCP roots must trigger on their dir and modules/gcp/**."
  }

  assert {
    condition     = module.workspace["aws-workload-dev"].trigger_patterns == tolist(["envs/aws/workload/**", "modules/aws/**"])
    error_message = "AWS roots must trigger on their dir and modules/aws/**."
  }

  assert {
    condition     = toset(module.workspace["saas-web"].trigger_patterns) == toset(["envs/saas/**", "modules/saas/**", "modules/supabase/**", "modules/vercel/**"])
    error_message = "the saas root must trigger on envs/saas and the saas/supabase/vercel module domains."
  }
}

# C2: no privileged speculative plan for a PR on the control plane.
run "speculative_plans_off_for_control_plane" {
  command = plan

  assert {
    condition = alltrue([
      for k in ["gcp-bootstrap", "gcp-organization", "gcp-projects", "gcp-network-hub", "aws-organization", "aws-security", "aws-backup", "aws-identity"] :
      module.workspace[k].speculative_enabled == false
    ])
    error_message = "control-plane workspaces must have speculative_enabled = false."
  }

  assert {
    condition     = module.workspace["gcp-workload-dev"].speculative_enabled == true && module.workspace["saas-web"].speculative_enabled == true
    error_message = "workload workspaces keep speculative PR plans."
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
    aws_plan_role_arns         = { "aws-security" = "arn:aws:iam::111111111111:role/tfc-plan" }
    aws_apply_role_arns        = { "aws-security" = "arn:aws:iam::111111111111:role/tfc-apply" }
    workspace_variables = {
      "aws-workload-dev" = { environment = { value = "dev" } }
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
    condition     = module.workspace["aws-security"].variable_keys == sort(["TFC_AWS_PROVIDER_AUTH", "TFC_AWS_PLAN_ROLE_ARN", "TFC_AWS_APPLY_ROLE_ARN"])
    error_message = "an AWS workspace with roles must get the three TFC_AWS_* env vars."
  }

  assert {
    condition     = output.dynamic_credential_workspaces.gcp == tolist(["gcp-organization"]) && output.dynamic_credential_workspaces.aws == tolist(["aws-security"])
    error_message = "credentials must be set only on the workspaces named in the input maps."
  }

  assert {
    condition     = module.workspace["aws-workload-dev"].variable_keys == tolist(["environment"])
    error_message = "workspace_variables must be set on the named workspace."
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
        tfc_plan_role_arns     = { prod = "arn:aws:iam::222222222222:role/tfc-plan", security_tooling = "arn:aws:iam::333333333333:role/tfc-plan" }
        tfc_apply_role_arns    = { prod = "arn:aws:iam::222222222222:role/tfc-apply", security_tooling = "arn:aws:iam::333333333333:role/tfc-apply" }
        tfc_workspace_bindings = { security_tooling = ["aws-security"] }
      }
    }
  }

  override_data {
    target = data.tfe_workspace.tfc_admin[0]
    values = { id = "ws-tfcadmin" }
  }

  assert {
    condition     = output.dynamic_credential_workspaces.gcp == tolist(["gcp-projects"]) && output.dynamic_credential_workspaces.aws == tolist(["aws-security", "aws-workload-prod"])
    error_message = "credentials read from upstream outputs must reach the mapped workspaces (explicit aws_workspace_account_keys and derived tfc_workspace_bindings)."
  }

  # tfc-admin must be allowed to read the upstream states it pulls outputs from.
  assert {
    condition     = contains(tfe_workspace_settings.this["gcp-bootstrap"].remote_state_consumer_ids, "ws-tfcadmin") && contains(tfe_workspace_settings.this["aws-organization"].remote_state_consumer_ids, "ws-tfcadmin")
    error_message = "tfc-admin must be a remote-state consumer of gcp-bootstrap and aws-organization when reading their outputs."
  }
}

# Control-plane run notifications (audit M-ops): a configured control-plane
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

run "team_access_per_project" {
  command = plan

  variables {
    platform_team_id = "team-platform1"
    viewer_team_ids  = ["team-viewers1"]
  }

  assert {
    condition     = tfe_team_project_access.this["gcp/platform"].access == "write" && tfe_team_project_access.this["aws/team-viewers1"].access == "read"
    error_message = "platform team gets write and viewer teams get read on every project."
  }

  assert {
    condition     = length(tfe_team_project_access.this) == 6
    error_message = "3 projects x (platform + 1 viewer) = 6 grants."
  }
}

run "policy_set_optional_and_advisory_source" {
  command = plan

  variables {
    enable_policy_sets = true
    vcs_repo           = { identifier = "acme/landing-zone", oauth_token_id = "ot-abc123" }
  }

  assert {
    condition     = tfe_policy_set.opa[0].kind == "opa" && tfe_policy_set.opa[0].policies_path == "policies/opa"
    error_message = "the policy set must be an OPA set sourced from policies/opa."
  }
}

run "policy_set_off_by_default" {
  command = plan

  assert {
    condition     = length(tfe_policy_set.opa) == 0
    error_message = "enable_policy_sets defaults to false."
  }
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
    condition     = module.workspace["tfc-admin"].speculative_enabled == false && module.workspace["tfc-admin"].trigger_patterns == tolist(["envs/tfc-admin/**", "modules/tfc/**"])
    error_message = "a self-managed tfc-admin workspace is control plane: no speculative plans, triggers on its dir + modules/tfc."
  }

  assert {
    condition     = contains(keys(tfe_project.this), "platform")
    error_message = "self-managed tfc-admin lands in the platform project."
  }
}
