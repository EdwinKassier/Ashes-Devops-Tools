# Root-level contract test. Mocks BOTH aws providers (default + us_east_1 alias)
# so no real credentials or role assumption happens, and overrides the upstream
# remote-state data sources with a known `contract` output. Asserts the values
# this root DERIVES from them — the workload account id, the TGW id, the region's
# IPAM pool and the log-archive bucket — not the overrides echoed back.
#
# validate already covers syntax/type wiring; this guards the remote-state
# contract shape the root depends on.

mock_provider "aws" {}
mock_provider "aws" { alias = "us_east_1" }
# tfe serves only the SaaS secret bridge (ephemeral "tfe_outputs"); mocked so
# no run contacts HCP Terraform. The default mock is a saas workspace that
# predates the bridge_version output; tfe.bridge_v4 publishes bridge_version 4.
mock_provider "tfe" {
  mock_ephemeral "tfe_outputs" {
    defaults = {
      values = {
        supabase_api_url           = "https://abcd.supabase.co"
        supabase_service_role_key  = "service-role-key-xxxx"
        supabase_database_password = "db-password-xxxx"
      }
      nonsensitive_values = {
        supabase_api_url = "https://abcd.supabase.co"
      }
    }
  }
}

mock_provider "tfe" {
  alias = "bridge_v4"

  mock_ephemeral "tfe_outputs" {
    defaults = {
      values = {
        supabase_api_url           = "https://abcd.supabase.co"
        supabase_service_role_key  = "service-role-key-xxxx"
        supabase_database_password = "db-password-xxxx"
        bridge_version             = 4
      }
      nonsensitive_values = {
        supabase_api_url = "https://abcd.supabase.co"
        bridge_version   = 4
      }
    }
  }
}

variables {
  # Isolate the suite from any committed config/landing-zone.yaml.
  landing_zone_config_path = ""
  landing_zone_name        = "acme"
  workload_account_key     = "workload_dev"
  log_archive_bucket_name  = null # sourced from the aws-security remote state
  kms_key_arn              = "arn:aws:kms:eu-west-2:222222222222:key/abcd-1234"
}

run "consumes_remote_state_contracts" {
  command = plan

  override_data {
    target = data.terraform_remote_state.aws_organization
    values = {
      outputs = {
        contract = {
          account_ids = { workload_dev = "222222222222" }
          account_role_arns = {
            workload_dev = "arn:aws:iam::222222222222:role/cross-account"
          }
        }
      }
    }
  }

  override_data {
    target = data.terraform_remote_state.aws_network
    values = {
      outputs = {
        contract = {
          tgw_id        = "tgw-000000000000abcd"
          ipam_pool_ids = { "eu-west-2" = "ipam-pool-eu-west-2-0" }
        }
      }
    }
  }

  override_data {
    target = data.terraform_remote_state.aws_security
    values = {
      outputs = {
        contract = {
          log_archive_bucket_name = "ashes-org-log-archive"
        }
      }
    }
  }

  # With var.log_archive_bucket_name = null, the central bucket name is derived
  # from the aws-security contract (its owner), not a hand-typed string.
  assert {
    condition     = local.log_archive_bucket_name == "ashes-org-log-archive"
    error_message = "the log-archive bucket name must be derived from the aws-security contract"
  }

  # The wrong-account guard is derived from the org contract's account_ids.
  assert {
    condition     = local.workload_account_id == "222222222222"
    error_message = "the workload account id must be derived from the aws-organization contract account_ids[workload_account_key]"
  }

  # The shared TGW id is derived from the network contract.
  assert {
    condition     = local.tgw_id == "tgw-000000000000abcd"
    error_message = "the TGW id must be derived from the aws-network contract"
  }

  # Provider default_tags: the canonical cost-allocation keys are written, and the
  # environment is derived from workload_account_key (workload_dev -> dev).
  assert {
    condition = (
      local.environment == "dev" &&
      local.aws_default_tags["Environment"] == "dev" &&
      local.aws_default_tags["Workspace"] == "aws-workload-dev" &&
      alltrue([for k in ["CostCenter", "Environment", "Owner", "ManagedBy", "LandingZone"] : contains(keys(local.aws_default_tags), k)])
    )
    error_message = "aws provider default_tags must carry CostCenter/Environment/Owner/ManagedBy/LandingZone with the derived environment"
  }

  # The spoke is named workload-<environment>, not a hard-coded "workload".
  assert {
    condition     = module.aws_workload.name == "workload-dev"
    error_message = "the spoke name must be derived as workload-<environment>"
  }

  # The spoke private tier routes 0.0.0.0/0 to the shared TGW from the network contract.
  assert {
    condition     = module.aws_workload.tgw_routes["private"][0].transit_gateway_id == "tgw-000000000000abcd"
    error_message = "the spoke must route its private tier to the shared TGW"
  }

  # The IPAM pool for this root's region is selected from the network contract.
  assert {
    condition     = local.ipam_pool_id == "ipam-pool-eu-west-2-0"
    error_message = "the IPAM pool must be the aws-network contract's pool for aws_region"
  }
}

# N-1 upgrade: an upstream state written before the `contract` output existed
# (not yet re-applied on this release) still plans, from the same keys as
# individual outputs. The fallback goes at v1.0 (UPGRADING.md).
run "pre_contract_upstream_state_still_plans" {
  command = plan

  override_data {
    target = data.terraform_remote_state.aws_organization
    values = { outputs = { account_ids = { workload_dev = "222222222222" } } }
  }
  override_data {
    target = data.terraform_remote_state.aws_network
    values = { outputs = { tgw_id = "tgw-000000000000abcd", ipam_pool_ids = { "eu-west-2" = "ipam-pool-eu-west-2-0" } } }
  }
  override_data {
    target = data.terraform_remote_state.aws_security
    values = { outputs = { log_archive_bucket_name = "ashes-org-log-archive" } }
  }

  assert {
    condition = (
      local.workload_account_id == "222222222222" &&
      local.tgw_id == "tgw-000000000000abcd" &&
      local.ipam_pool_id == "ipam-pool-eu-west-2-0" &&
      local.log_archive_bucket_name == "ashes-org-log-archive"
    )
    error_message = "a pre-contract upstream state (individual outputs only) must still resolve every contract value"
  }
}

# SaaS secret bridge: opt-in, default off; when
# enabled it writes the Supabase connection into an AWS Secrets Manager secret.
run "saas_secret_bridge_default_off" {
  command = plan

  override_data {
    target = data.terraform_remote_state.aws_organization
    values = { outputs = { contract = { account_ids = { workload_dev = "222222222222" }, account_role_arns = { workload_dev = "arn:aws:iam::222222222222:role/cross-account" } } } }
  }
  override_data {
    target = data.terraform_remote_state.aws_network
    values = { outputs = { contract = { tgw_id = "tgw-000000000000abcd", ipam_pool_ids = { "eu-west-2" = "ipam-pool-eu-west-2-0" } } } }
  }
  override_data {
    target = data.terraform_remote_state.aws_security
    values = { outputs = { contract = { log_archive_bucket_name = "ashes-org-log-archive" } } }
  }

  assert {
    condition     = length(aws_secretsmanager_secret.saas_bridge) == 0
    error_message = "the SaaS secret bridge must create nothing when disabled (default)."
  }
}

run "saas_secret_bridge_creates_secret_when_enabled" {
  command = plan

  variables {
    enable_saas_secret_bridge = true
    saas_workspace_name       = "saas-web"
    saas_secret_reader_arns   = ["arn:aws:iam::222222222222:role/app-task-role"]
  }

  override_data {
    target = data.terraform_remote_state.aws_organization
    values = { outputs = { contract = { account_ids = { workload_dev = "222222222222" }, account_role_arns = { workload_dev = "arn:aws:iam::222222222222:role/cross-account" } } } }
  }
  override_data {
    target = data.terraform_remote_state.aws_network
    values = { outputs = { contract = { tgw_id = "tgw-000000000000abcd", ipam_pool_ids = { "eu-west-2" = "ipam-pool-eu-west-2-0" } } } }
  }
  override_data {
    target = data.terraform_remote_state.aws_security
    values = { outputs = { contract = { log_archive_bucket_name = "ashes-org-log-archive" } } }
  }

  assert {
    condition     = length(aws_secretsmanager_secret.saas_bridge) == 1
    error_message = "enabling the bridge must create exactly one Secrets Manager secret."
  }

  assert {
    condition     = length(aws_secretsmanager_secret_policy.saas_bridge) == 1
    error_message = "the bridge must attach a resource policy granting the reader roles access."
  }
}

# App services golden path: the default (services = {}) creates nothing; one
# services entry wires an ECR repo, a Fargate service behind an INTERNAL ALB in
# the spoke's private tier, and a GitHub OIDC deploy role pinned to the exact
# repo + environment subject. Full IAM-JSON assertions live in
# modules/aws/stages/app-services/tests.
run "app_services_default_creates_nothing" {
  command = plan

  override_data {
    target = data.terraform_remote_state.aws_organization
    values = { outputs = { contract = { account_ids = { workload_dev = "222222222222" }, account_role_arns = { workload_dev = "arn:aws:iam::222222222222:role/cross-account" } } } }
  }
  override_data {
    target = data.terraform_remote_state.aws_network
    values = { outputs = { contract = { tgw_id = "tgw-000000000000abcd", ipam_pool_ids = { "eu-west-2" = "ipam-pool-eu-west-2-0" } } } }
  }
  override_data {
    target = data.terraform_remote_state.aws_security
    values = { outputs = { contract = { log_archive_bucket_name = "ashes-org-log-archive" } } }
  }

  assert {
    condition     = length(output.app_services) == 0 && output.app_alb_dns_name == null && output.github_oidc_provider_arn == null
    error_message = "services = {} must create no app-services resources (no cluster, ALB, repo or OIDC provider)."
  }
}

run "app_services_one_service" {
  command = plan

  variables {
    enable_github_oidc = true
    services = {
      orders = {
        github   = { repository = "acme/orders" }
        database = {}
      }
    }
  }

  override_data {
    target = data.terraform_remote_state.aws_organization
    values = { outputs = { contract = { account_ids = { workload_dev = "222222222222" }, account_role_arns = { workload_dev = "arn:aws:iam::222222222222:role/cross-account" } } } }
  }
  override_data {
    target = data.terraform_remote_state.aws_network
    values = { outputs = { contract = { tgw_id = "tgw-000000000000abcd", ipam_pool_ids = { "eu-west-2" = "ipam-pool-eu-west-2-0" } } } }
  }
  override_data {
    target = data.terraform_remote_state.aws_security
    values = { outputs = { contract = { log_archive_bucket_name = "ashes-org-log-archive" } } }
  }

  assert {
    condition     = keys(output.app_services) == ["orders"] && output.app_services["orders"].ecr_repository_name == "orders" && output.app_services["orders"].ecs_cluster_name == "dev-apps"
    error_message = "one services entry must yield an ECR repo and a service on the shared dev-apps cluster."
  }

  assert {
    condition     = output.github_oidc_subjects["orders"] == "repo:acme/orders:environment:dev"
    error_message = "the deploy role must trust exactly repo:<org>/<repo>:environment:<environment>."
  }

  assert {
    condition     = module.app_services.alb_internal == true
    error_message = "the shared ALB must be internal by default."
  }

  assert {
    condition     = output.app_services["orders"].database_public == false
    error_message = "the service database must not be publicly accessible."
  }
}

# landing_zone_name has no default and rejects the upstream placeholders.
run "rejects_placeholder_landing_zone_name" {
  command = plan

  variables {
    landing_zone_name = "ashes"
  }

  override_data {
    target = data.terraform_remote_state.aws_organization
    values = {
      outputs = {
        contract = {
          account_ids = { workload_dev = "222222222222" }
          account_role_arns = {
            workload_dev = "arn:aws:iam::222222222222:role/cross-account"
          }
        }
      }
    }
  }

  override_data {
    target = data.terraform_remote_state.aws_network
    values = {
      outputs = {
        contract = {
          tgw_id        = "tgw-000000000000abcd"
          ipam_pool_ids = { "eu-west-2" = "ipam-pool-eu-west-2-0" }
        }
      }
    }
  }

  override_data {
    target = data.terraform_remote_state.aws_security
    values = {
      outputs = {
        contract = {
          log_archive_bucket_name = "ashes-org-log-archive"
        }
      }
    }
  }

  expect_failures = [var.landing_zone_name]
}

# SaaS bridge write-only: the values come from ephemeral "tfe_outputs" (never in
# this root's plan or state) and go to secret_string_wo. The version is
# non-ephemeral: saas_bridge_version / saas.bridge_rotation, which must match the
# bridge_version the saas workspace publishes.
run "bridge_uses_write_only_secret" {
  command = plan

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
    tfe           = tfe.bridge_v4
  }

  variables {
    enable_saas_secret_bridge = true
    saas_workspace_name       = "saas-web"
    saas_secret_reader_arns   = ["arn:aws:iam::222222222222:role/app-task-role"]
    saas_bridge_version       = 4
  }

  override_data {
    target = data.terraform_remote_state.aws_organization
    values = { outputs = { contract = { account_ids = { workload_dev = "222222222222" }, account_role_arns = { workload_dev = "arn:aws:iam::222222222222:role/cross-account" } } } }
  }
  override_data {
    target = data.terraform_remote_state.aws_network
    values = { outputs = { contract = { tgw_id = "tgw-000000000000abcd", ipam_pool_ids = { "eu-west-2" = "ipam-pool-eu-west-2-0" } } } }
  }
  override_data {
    target = data.terraform_remote_state.aws_security
    values = { outputs = { contract = { log_archive_bucket_name = "ashes-org-log-archive" } } }
  }

  assert {
    condition     = aws_secretsmanager_secret_version.saas_bridge[0].secret_string == null
    error_message = "the bridged secret must be written with the write-only secret_string_wo, never secret_string."
  }

  assert {
    condition     = aws_secretsmanager_secret_version.saas_bridge[0].secret_string_wo_version == 4
    error_message = "secret_string_wo_version must equal saas_bridge_version."
  }
}

# The version comes from saas.bridge_rotation in the config file when the
# variable is unset.
run "bridge_version_from_config_file" {
  command = plan

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
    tfe           = tfe.bridge_v4
  }

  variables {
    landing_zone_config_path  = "tests/fixtures/landing-zone-saas-bridge.yaml"
    enable_saas_secret_bridge = true
    saas_workspace_name       = "saas-web"
    saas_secret_reader_arns   = ["arn:aws:iam::222222222222:role/app-task-role"]
  }

  override_data {
    target = data.terraform_remote_state.aws_organization
    values = { outputs = { contract = { account_ids = { workload_dev = "222222222222" }, account_role_arns = { workload_dev = "arn:aws:iam::222222222222:role/cross-account" } } } }
  }
  override_data {
    target = data.terraform_remote_state.aws_network
    values = { outputs = { contract = { tgw_id = "tgw-000000000000abcd", ipam_pool_ids = { "eu-west-2" = "ipam-pool-eu-west-2-0" } } } }
  }
  override_data {
    target = data.terraform_remote_state.aws_security
    values = { outputs = { contract = { log_archive_bucket_name = "ashes-org-log-archive" } } }
  }

  assert {
    condition     = aws_secretsmanager_secret_version.saas_bridge[0].secret_string_wo_version == 4
    error_message = "secret_string_wo_version must come from saas.bridge_rotation when saas_bridge_version is unset."
  }
}

# A saas producer that has not applied the bridge_version output yet counts as
# version 1, the default.
run "bridge_version_defaults_to_1_without_producer_output" {
  command = plan

  variables {
    enable_saas_secret_bridge = true
    saas_workspace_name       = "saas-web"
    saas_secret_reader_arns   = ["arn:aws:iam::222222222222:role/app-task-role"]
  }

  override_data {
    target = data.terraform_remote_state.aws_organization
    values = { outputs = { contract = { account_ids = { workload_dev = "222222222222" }, account_role_arns = { workload_dev = "arn:aws:iam::222222222222:role/cross-account" } } } }
  }
  override_data {
    target = data.terraform_remote_state.aws_network
    values = { outputs = { contract = { tgw_id = "tgw-000000000000abcd", ipam_pool_ids = { "eu-west-2" = "ipam-pool-eu-west-2-0" } } } }
  }
  override_data {
    target = data.terraform_remote_state.aws_security
    values = { outputs = { contract = { log_archive_bucket_name = "ashes-org-log-archive" } } }
  }

  assert {
    condition     = aws_secretsmanager_secret_version.saas_bridge[0].secret_string_wo_version == 1
    error_message = "without saas_bridge_version or saas.bridge_rotation the write-only version must be 1."
  }
}

# Bumped here but not yet published by the saas workspace: the plan fails
# instead of writing the old values under the new version.
run "bridge_version_ahead_of_producer_fails" {
  command = plan

  variables {
    enable_saas_secret_bridge = true
    saas_workspace_name       = "saas-web"
    saas_secret_reader_arns   = ["arn:aws:iam::222222222222:role/app-task-role"]
    saas_bridge_version       = 2
  }

  override_data {
    target = data.terraform_remote_state.aws_organization
    values = { outputs = { contract = { account_ids = { workload_dev = "222222222222" }, account_role_arns = { workload_dev = "arn:aws:iam::222222222222:role/cross-account" } } } }
  }
  override_data {
    target = data.terraform_remote_state.aws_network
    values = { outputs = { contract = { tgw_id = "tgw-000000000000abcd", ipam_pool_ids = { "eu-west-2" = "ipam-pool-eu-west-2-0" } } } }
  }
  override_data {
    target = data.terraform_remote_state.aws_security
    values = { outputs = { contract = { log_archive_bucket_name = "ashes-org-log-archive" } } }
  }

  expect_failures = [ephemeral.tfe_outputs.saas]
}

run "bridge_off_reads_nothing" {
  command = plan

  override_data {
    target = data.terraform_remote_state.aws_organization
    values = { outputs = { contract = { account_ids = { workload_dev = "222222222222" }, account_role_arns = { workload_dev = "arn:aws:iam::222222222222:role/cross-account" } } } }
  }
  override_data {
    target = data.terraform_remote_state.aws_network
    values = { outputs = { contract = { tgw_id = "tgw-000000000000abcd", ipam_pool_ids = { "eu-west-2" = "ipam-pool-eu-west-2-0" } } } }
  }
  override_data {
    target = data.terraform_remote_state.aws_security
    values = { outputs = { contract = { log_archive_bucket_name = "ashes-org-log-archive" } } }
  }

  assert {
    condition = (
      length(aws_secretsmanager_secret.saas_bridge) == 0 &&
      length(aws_secretsmanager_secret_version.saas_bridge) == 0 &&
      length(aws_secretsmanager_secret_policy.saas_bridge) == 0
    )
    error_message = "with the bridge off, no bridge resource is planned."
  }
}
