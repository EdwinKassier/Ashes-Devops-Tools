# Single-source configuration: with the AWS inputs unset, the root reads them
# from the landing-zone config file (a fixture here, config/landing-zone.yaml in
# a real estate); explicit variables still win; missing values and untouched
# placeholders fail fast.

mock_provider "aws" {}

variables {
  landing_zone_config_path = "tests/fixtures/landing-zone.yaml"
}

override_module {
  target = module.aws_organization
  outputs = {
    organization_id        = "o-abcdefghij"
    management_account_id  = "012345678901"
    organization_root_id   = "r-abcd"
    ou_ids                 = {}
    account_ids            = {}
    account_role_arns      = {}
    tfc_plan_role_arns     = {}
    tfc_apply_role_arns    = {}
    tfc_workspace_bindings = {}
  }
}

# tfc-management-roles reads the partition / caller identity; mocks return
# random strings the provider's ARN validators reject, so pin real shapes.
override_data {
  target = module.aws_organization.module.tfc_management_roles[0].data.aws_partition.current
  values = { partition = "aws" }
}

override_data {
  target = module.aws_organization.module.tfc_management_roles[0].data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

run "values_come_from_config_file" {
  command = plan

  assert {
    condition     = local.landing_zone_name == "cfgco" && local.owner == "cfg-platform" && local.cost_center == "cc-1234" && local.aws_region == "eu-west-1"
    error_message = "unset scalars must fall back to org.name / org.owner / org.cost_center / org.regions.aws."
  }

  # A quoted account ID keeps its leading zero.
  assert {
    condition     = local.management_account_id == "012345678901" && local.tfc_organization == "cfg-tfc" && local.log_archive_bucket_name == "cfgco-org-log-archive"
    error_message = "management_account_id / tfc_organization / log_archive_bucket_name must come from the config file."
  }

  assert {
    condition     = local.terraform_run_role_arn == "arn:aws:iam::012345678901:role/tfc-mgmt-apply" && local.break_glass_role_arn == "arn:aws:iam::012345678901:role/break-glass" && join(",", local.allowed_regions) == "eu-west-1,eu-west-2"
    error_message = "role ARNs and allowed_regions must come from the config file."
  }

  assert {
    condition     = length(local.accounts) == 6 && local.accounts["network"].email == "aws+network@cfg.test" && local.accounts["network"].tags.tier == "core" && length(local.workload_accounts) == 2
    error_message = "accounts / workload_accounts must come from aws.accounts / aws.workload_accounts (normalised, tags kept)."
  }

  # No aws_project in the config: <project_name_prefix>aws, matching tfc-admin.
  assert {
    condition     = local.tfc_project == "cfg-aws"
    error_message = "tfc_project must default to <org.tfc.project_name_prefix>aws (the project tfc-admin creates)."
  }

  # Foundational bindings kept; workload bindings derived from
  # aws.workload_environments, grouping envs that share an account key.
  assert {
    condition = (
      join(",", local.tfc_workspace_bindings["shared_services"].workspaces) == "aws-identity,aws-shared-services" &&
      toset(local.tfc_workspace_bindings["workload_nonprod"].workspaces) == toset(["aws-workload-dev", "aws-workload-staging"]) &&
      join(",", local.tfc_workspace_bindings["workload_prod"].workspaces) == "aws-workload-prod"
    )
    error_message = "tfc_workspace_bindings must merge the foundational defaults with the config-derived workload bindings."
  }
}

run "guard_alert_inputs_come_from_config_file" {
  command = plan

  assert {
    condition     = join(",", local.aws_enabled_regions) == "eu-west-1,us-east-1" && join(",", local.guard_alert_emails) == "secops@cfg.test"
    error_message = "aws_enabled_regions / guard_alert_emails must fall back to aws.enabled_regions / aws.guard_alert_emails."
  }
}

run "guard_alert_inputs_variables_win" {
  command = plan

  variables {
    aws_enabled_regions = ["eu-west-2"]
    guard_alert_emails  = []
  }

  assert {
    condition     = join(",", local.aws_enabled_regions) == "eu-west-2" && length(local.guard_alert_emails) == 0
    error_message = "explicit aws_enabled_regions / guard_alert_emails must win over the config file."
  }
}

run "tfc_project_default_without_config_prefix" {
  command = plan

  variables {
    landing_zone_name      = "acme"
    management_account_id  = "111111111111"
    terraform_run_role_arn = "arn:aws:iam::111111111111:role/tfc-run-role"
    break_glass_role_arn   = "arn:aws:iam::111111111111:role/break-glass"
    tfc_organization       = "acme"
    accounts = {
      log_archive = { email = "aws+log-archive@acme.test", ou = "Security" }
    }
    log_archive_bucket_name  = "acme-org-log-archive"
    landing_zone_config_path = ""
  }

  assert {
    condition     = local.tfc_project == "landing-zone-aws" && length(local.tfc_workspace_bindings) == 6
    error_message = "with no config file tfc_project defaults to landing-zone-aws (tfc-admin's default AWS project) and only the foundational bindings exist."
  }
}

run "explicit_variables_win_over_config" {
  command = plan

  variables {
    landing_zone_name     = "acme"
    management_account_id = "111111111111"
    tfc_project           = "Explicit Project"
    allowed_regions       = ["us-east-1"]
    tfc_workspace_bindings = {
      network = { workspaces = ["aws-network"] }
    }
  }

  assert {
    condition     = local.landing_zone_name == "acme" && local.management_account_id == "111111111111" && local.tfc_project == "Explicit Project" && join(",", local.allowed_regions) == "us-east-1" && join(",", keys(local.tfc_workspace_bindings)) == "network"
    error_message = "an explicit variable must take precedence over the config file."
  }
}

run "missing_config_and_variables_fails" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/does-not-exist.yaml"
  }

  expect_failures = [
    var.landing_zone_name,
    var.management_account_id,
    var.terraform_run_role_arn,
    var.break_glass_role_arn,
    var.log_archive_bucket_name,
    var.tfc_organization,
    var.accounts,
  ]
}

run "untouched_placeholders_rejected" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-placeholder.yaml"
  }

  expect_failures = [
    var.landing_zone_name,
    var.management_account_id,
    var.terraform_run_role_arn,
    var.break_glass_role_arn,
    var.accounts,
  ]
}

# split_workload_projects: workload-only accounts trust the workloads project
# (where tfc-admin puts aws-workload-<env>); foundational accounts keep the
# default project.
run "split_workload_projects_trust_the_workloads_project" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-split.yaml"
  }

  assert {
    condition = (
      local.tfc_workspace_bindings["workload_prod"].project == "cfg-aws-workloads" &&
      local.tfc_workspace_bindings["workload_nonprod"].project == "cfg-aws-workloads" &&
      local.tfc_workspace_bindings["security_tooling"].project == null
    )
    error_message = "with split_workload_projects, workload accounts must trust <prefix>aws-workloads and foundational ones the default project."
  }
}
