# The workspace catalog (local.catalog in main.tf) is the one hand-maintained
# workspace inventory: the workspace set, the run-trigger DAG, the remote-state
# consumer graph and the multi-account alias lists are all derived from it.
#
# The *_names_unchanged runs pin the full for_each key sets of every
# workspace-keyed collection to literal lists, so a catalog refactor that would
# move or recreate a tfe_workspace, run trigger, variable or team grant fails
# here instead of in a real plan.

mock_provider "tfe" {}

variables {
  tfc_organization = "acme"
  environments = {
    dev  = {}
    prod = {}
  }
  enable_gcp                       = true
  enable_aws                       = true
  enable_saas                      = true
  saas_workspaces                  = ["web"]
  landing_zone_config_path         = ""
  workspace_variables_file         = null
  manage_tfc_admin_workspace       = false
  security_team_id                 = "team-security1"
  enable_unguarded_destroy_warning = false
}

# Default test config (the root.tftest.hcl estate) with every team input set.
run "default_catalog_names_unchanged" {
  command = plan

  variables {
    platform_team_id                = "team-platform1"
    control_plane_approvers_team_id = "team-approvers1"
    viewer_team_ids                 = ["team-viewer1"]
    saas_outputs_reader_team_id     = "team-saasread1"
  }

  assert {
    condition = output.workspace_names == tolist([
      "aws-backup", "aws-identity", "aws-network", "aws-organization", "aws-security", "aws-shared-services",
      "aws-workload-dev", "aws-workload-prod",
      "gcp-bootstrap", "gcp-guardrails", "gcp-network-hub", "gcp-organization", "gcp-projects",
      "gcp-workload-dev", "gcp-workload-prod",
      "saas-web",
    ])
    error_message = "the catalog must declare exactly the pre-catalog workspace names (module.workspace keys)."
  }

  assert {
    condition     = toset(keys(tfe_workspace_settings.this)) == toset(output.workspace_names)
    error_message = "tfe_workspace_settings must stay keyed by workspace name."
  }

  assert {
    condition = toset(keys(tfe_run_trigger.dag)) == toset([
      "tfc-admin->aws-organization",
      "gcp-bootstrap->gcp-organization", "gcp-organization->gcp-projects", "gcp-projects->gcp-network-hub",
      "gcp-network-hub->gcp-workload-dev", "gcp-network-hub->gcp-workload-prod",
      "aws-organization->aws-backup", "aws-organization->aws-identity", "aws-organization->aws-network",
      "aws-organization->aws-security", "aws-organization->aws-shared-services",
      "aws-network->aws-workload-dev", "aws-network->aws-workload-prod",
      "aws-security->aws-workload-dev", "aws-security->aws-workload-prod",
    ])
    error_message = "the run-trigger keys must be the pre-catalog \"<source>-><downstream>\" set (gcp-bootstrap runs locally, so tfc-admin triggers aws-organization only)."
  }

  assert {
    condition = toset(keys(tfe_team_project_access.this)) == toset([
      "aws/approvers", "aws/platform", "aws/team-viewer1",
      "gcp/approvers", "gcp/platform", "gcp/team-viewer1",
      "saas/platform", "saas/team-viewer1",
      "guardrails/security",
    ])
    error_message = "the project team grants must keep their <project>/<team> keys."
  }

  assert {
    condition     = toset(keys(tfe_team_access.platform_workload)) == toset(["aws-workload-dev", "aws-workload-prod", "gcp-workload-dev", "gcp-workload-prod"])
    error_message = "the platform workspace-level write grants must stay keyed by workload workspace name."
  }

  assert {
    condition     = toset(keys(tfe_team_access.saas_outputs_reader)) == toset(["saas-web"])
    error_message = "the saas-outputs-reader grants must stay keyed by saas-<name>."
  }

  assert {
    condition     = toset(keys(tfe_project.this)) == toset(["aws", "gcp", "guardrails", "saas"])
    error_message = "the project keys must be unchanged."
  }

  assert {
    condition = alltrue([
      module.workspace["gcp-workload-dev"].variable_keys == tolist(["environment"]),
      module.workspace["aws-workload-prod"].variable_keys == tolist(["environment"]),
      module.workspace["saas-web"].variable_keys == tolist(["stack"]),
      module.workspace["saas-web"].variable_values["stack"] == "web",
      module.workspace["gcp-workload-prod"].variable_values["environment"] == "prod",
      length(module.workspace["aws-security"].variable_keys) == 0,
    ])
    error_message = "the derived per-workspace variables (and so their tfe_variable keys) must be unchanged."
  }

  assert {
    condition = jsonencode(output.remote_state_consumers) == jsonencode({
      "gcp-bootstrap"    = ["gcp-organization", "gcp-projects"]
      "gcp-organization" = ["gcp-network-hub", "gcp-projects", "gcp-workload-dev", "gcp-workload-prod"]
      "gcp-projects"     = ["gcp-network-hub", "gcp-workload-dev", "gcp-workload-prod"]
      "gcp-network-hub"  = ["gcp-workload-dev", "gcp-workload-prod"]
      "aws-organization" = ["aws-backup", "aws-identity", "aws-network", "aws-security", "aws-shared-services", "aws-workload-dev", "aws-workload-prod"]
      "aws-network"      = ["aws-workload-dev", "aws-workload-prod"]
      "aws-security"     = ["aws-workload-dev", "aws-workload-prod"]
    })
    error_message = "the remote-state consumer graph must be the pre-catalog one."
  }

  assert {
    condition = alltrue([
      module.workspace["gcp-guardrails"].working_directory == "envs/gcp/guardrails",
      length(module.workspace["gcp-guardrails"].variable_set_labels) == 0,
      module.workspace["aws-workload-dev"].working_directory == "envs/aws/workload",
      module.workspace["saas-web"].working_directory == "envs/saas",
    ])
    error_message = "working directories and the guardrails variable-set exclusion must be unchanged."
  }
}

# A multi-environment estate: four environments, two saas stacks, split
# workload projects, a self-managed tfc-admin, remote gcp-bootstrap and the
# multi-account alias roles.
run "multi_environment_catalog_names_unchanged" {
  command = plan

  variables {
    environments = {
      dev     = { is_production = false, aws_account_key = "workload_dev" }
      staging = { is_production = false }
      prod    = { is_production = true, aws_account_key = "workload_prod" }
      qa      = {}
    }
    saas_workspaces               = ["web", "admin"]
    manage_tfc_admin_workspace    = true
    import_tfc_admin_workspace    = false
    tfc_admin_team_id             = "team-tfcadmin1"
    platform_team_id              = "team-platform1"
    split_workload_projects       = true
    workspace_execution_modes     = {}
    aws_management_plan_role_arn  = "arn:aws:iam::111111111111:role/p"
    aws_management_apply_role_arn = "arn:aws:iam::111111111111:role/a"
    aws_alias_role_arns = {
      "aws-security" = {
        security_tooling = { plan_role_arn = "arn:aws:iam::111111111111:role/p", apply_role_arn = "arn:aws:iam::111111111111:role/a" }
        log_archive      = { plan_role_arn = "arn:aws:iam::222222222222:role/p", apply_role_arn = "arn:aws:iam::222222222222:role/a" }
        forensics        = { plan_role_arn = "arn:aws:iam::333333333333:role/p", apply_role_arn = "arn:aws:iam::333333333333:role/a" }
      }
    }
    extra_remote_state_consumers = { "saas-web" = ["gcp-workload-dev"] }
  }

  assert {
    condition = output.workspace_names == tolist([
      "aws-backup", "aws-identity", "aws-network", "aws-organization", "aws-security", "aws-shared-services",
      "aws-workload-dev", "aws-workload-prod", "aws-workload-qa", "aws-workload-staging",
      "gcp-bootstrap", "gcp-guardrails", "gcp-network-hub", "gcp-organization", "gcp-projects",
      "gcp-workload-dev", "gcp-workload-prod", "gcp-workload-qa", "gcp-workload-staging",
      "saas-admin", "saas-web", "tfc-admin",
    ])
    error_message = "every per_environment family must expand to <key>-<env> with the pre-catalog names."
  }

  assert {
    condition     = toset(keys(tfe_workspace_settings.this)) == toset(output.workspace_names)
    error_message = "tfe_workspace_settings must stay keyed by workspace name."
  }

  assert {
    condition = toset(keys(tfe_run_trigger.dag)) == toset([
      "tfc-admin->aws-organization", "tfc-admin->gcp-bootstrap",
      "gcp-bootstrap->gcp-organization", "gcp-organization->gcp-projects", "gcp-projects->gcp-network-hub",
      "gcp-network-hub->gcp-workload-dev", "gcp-network-hub->gcp-workload-prod",
      "gcp-network-hub->gcp-workload-qa", "gcp-network-hub->gcp-workload-staging",
      "aws-organization->aws-backup", "aws-organization->aws-identity", "aws-organization->aws-network",
      "aws-organization->aws-security", "aws-organization->aws-shared-services",
      "aws-network->aws-workload-dev", "aws-network->aws-workload-prod",
      "aws-network->aws-workload-qa", "aws-network->aws-workload-staging",
      "aws-security->aws-workload-dev", "aws-security->aws-workload-prod",
      "aws-security->aws-workload-qa", "aws-security->aws-workload-staging",
    ])
    error_message = "the run-trigger keys must be the pre-catalog set for four environments."
  }

  assert {
    condition = toset(keys(tfe_team_project_access.this)) == toset([
      "aws/platform", "aws-workloads/platform", "gcp/platform", "gcp-workloads/platform",
      "saas/platform", "platform/platform", "guardrails/security",
    ])
    error_message = "the project team grants must keep their <project>/<team> keys."
  }

  assert {
    condition     = length(tfe_team_access.platform_workload) == 0 && length(tfe_team_access.tfc_admin) == 1
    error_message = "split projects need no workspace-level platform write; tfc-admin keeps its explicit grant."
  }

  assert {
    condition     = toset(keys(tfe_project.this)) == toset(["aws", "aws-workloads", "gcp", "gcp-workloads", "guardrails", "platform", "saas"])
    error_message = "the project keys must be unchanged."
  }

  assert {
    condition = alltrue([
      module.workspace["aws-security"].variable_keys == sort(tolist([
        "TFC_AWS_PROVIDER_AUTH", "TFC_AWS_PLAN_ROLE_ARN", "TFC_AWS_APPLY_ROLE_ARN",
        "TFC_AWS_PROVIDER_AUTH_security_tooling", "TFC_AWS_PLAN_ROLE_ARN_security_tooling", "TFC_AWS_APPLY_ROLE_ARN_security_tooling",
        "TFC_AWS_PROVIDER_AUTH_log_archive", "TFC_AWS_PLAN_ROLE_ARN_log_archive", "TFC_AWS_APPLY_ROLE_ARN_log_archive",
        "TFC_AWS_PROVIDER_AUTH_forensics", "TFC_AWS_PLAN_ROLE_ARN_forensics", "TFC_AWS_APPLY_ROLE_ARN_forensics",
      ])),
      module.workspace["aws-organization"].variable_keys == tolist(["TFC_AWS_APPLY_ROLE_ARN", "TFC_AWS_PLAN_ROLE_ARN", "TFC_AWS_PROVIDER_AUTH"]),
      # aws-backup's backup alias has no roles, so its management default is withheld.
      length(module.workspace["aws-backup"].variable_keys) == 0,
      module.workspace["aws-workload-dev"].variable_keys == tolist(["environment", "workload_account_key"]),
      module.workspace["aws-workload-qa"].variable_keys == tolist(["environment"]),
      module.workspace["saas-admin"].variable_values["stack"] == "admin",
    ])
    error_message = "the derived per-workspace variables (credential, alias, environment and stack keys) must be unchanged."
  }

  assert {
    condition = alltrue([
      for ws in ["gcp-workload-dev", "gcp-workload-staging", "aws-workload-dev", "aws-workload-staging"] :
      module.workspace[ws].queue_all_runs && module.workspace[ws].auto_apply_run_trigger
      ]) && alltrue([
      for ws in ["gcp-workload-prod", "gcp-workload-qa", "aws-workload-prod", "aws-workload-qa", "gcp-guardrails", "tfc-admin"] :
      !module.workspace[ws].queue_all_runs && !module.workspace[ws].auto_apply_run_trigger
    ])
    error_message = "only explicitly non-production workloads queue all runs and auto-apply run triggers."
  }

  assert {
    condition = alltrue([
      output.remote_state_consumers["saas-web"] == tolist(["gcp-workload-dev"]),
      output.remote_state_consumers["gcp-network-hub"] == tolist(["gcp-workload-dev", "gcp-workload-prod", "gcp-workload-qa", "gcp-workload-staging"]),
      !contains(keys(output.remote_state_consumers), "saas-admin"),
      !contains(keys(output.remote_state_consumers), "gcp-guardrails"),
    ])
    error_message = "the consumer graph must merge the catalog reads with extra_remote_state_consumers."
  }
}

# Every derived collection agrees with the catalog: a workspace's inbound run
# triggers are exactly its managed upstreams, each producer's consumers are
# exactly the workspaces that read it, and each multi-account root gets one
# TFC_AWS_PROVIDER_AUTH_<alias> per aws_member_aliases entry.
run "catalog_drives_workspaces_and_triggers" {
  command = plan

  variables {
    environments = {
      dev     = { is_production = false }
      staging = { is_production = false }
      prod    = {}
    }
    manage_tfc_admin_workspace    = true
    import_tfc_admin_workspace    = false
    workspace_execution_modes     = {}
    aws_management_plan_role_arn  = "arn:aws:iam::111111111111:role/p"
    aws_management_apply_role_arn = "arn:aws:iam::111111111111:role/a"
    aws_alias_role_arns = {
      "aws-security" = {
        security_tooling = { plan_role_arn = "arn:aws:iam::111111111111:role/p", apply_role_arn = "arn:aws:iam::111111111111:role/a" }
        log_archive      = { plan_role_arn = "arn:aws:iam::222222222222:role/p", apply_role_arn = "arn:aws:iam::222222222222:role/a" }
        forensics        = { plan_role_arn = "arn:aws:iam::333333333333:role/p", apply_role_arn = "arn:aws:iam::333333333333:role/a" }
      }
      "aws-backup" = {
        backup = { plan_role_arn = "arn:aws:iam::444444444444:role/p", apply_role_arn = "arn:aws:iam::444444444444:role/a" }
      }
    }
  }

  assert {
    condition     = sort(keys(output.workspace_catalog)) == output.workspace_names
    error_message = "every managed workspace must come from the catalog."
  }

  assert {
    condition = alltrue([
      for ws, w in output.workspace_catalog :
      toset([for t in output.run_triggers : split("->", t)[0] if split("->", t)[1] == ws]) ==
      toset([for u in w.upstreams : u if contains(output.workspace_names, u)])
    ])
    error_message = "each workspace's inbound run triggers must be exactly its catalog upstreams."
  }

  assert {
    condition = alltrue([
      for p in output.workspace_names :
      toset(lookup(output.remote_state_consumers, p, [])) == toset([for ws, w in output.workspace_catalog : ws if contains(w.reads, p)])
    ])
    error_message = "each producer's remote-state consumers must be exactly the catalog entries that read it."
  }

  assert {
    condition = alltrue(flatten([
      for ws, w in output.workspace_catalog : [
        for a in w.aws_member_aliases : contains(module.workspace[ws].variable_keys, "TFC_AWS_PROVIDER_AUTH_${a}")
      ]
    ])) && output.workspace_catalog["aws-backup"].aws_member_aliases == tolist(["backup"])
    error_message = "each multi-account workspace must get TFC_AWS_*_<alias> vars for every catalog aws_member_aliases entry."
  }

  assert {
    condition = alltrue([
      for ws, w in output.workspace_catalog :
      module.workspace[ws].working_directory == w.dir &&
      (w.environment == null ? true : endswith(ws, "-${w.environment}"))
    ])
    error_message = "each workspace's working directory is its catalog dir, and a per_environment member is named <key>-<env>."
  }

  assert {
    condition = alltrue([
      output.workspace_catalog["gcp-workload-staging"].environment == "staging",
      output.workspace_catalog["saas-web"].environment == "web",
      output.workspace_catalog["gcp-network-hub"].environment == null,
      output.workspace_catalog["tfc-admin"].cloud == "platform",
    ])
    error_message = "per_environment families expand over the cloud's environments (saas: saas_workspaces)."
  }
}
