# Root-level contract test. Mocks BOTH aws providers (default + us_east_1 alias)
# so no real credentials or role assumption happens, and overrides BOTH upstream
# remote-state data sources with a known cross-root contract. Asserts the keys
# this root consumes — account_role_arns[workload_account_key] (both providers),
# tgw_id and ipam_pool_ids[aws_region] (aws_network) — are readable.
#
# validate already covers syntax/type wiring; this guards the remote-state
# contract shape the root depends on.

mock_provider "aws" {}
mock_provider "aws" { alias = "us_east_1" }

variables {
  # Isolate the suite from any committed config/landing-zone.yaml.
  landing_zone_config_path = ""
  landing_zone_name        = "acme"
  workload_account_key     = "workload_dev"
  log_archive_bucket_name  = null # sourced from the aws-security remote state
  config_role_arn          = "arn:aws:iam::222222222222:role/config-recorder"
  kms_key_arn              = "arn:aws:kms:eu-west-2:222222222222:key/abcd-1234"
}

run "consumes_remote_state_contracts" {
  command = plan

  override_data {
    target = data.terraform_remote_state.aws_organization
    values = {
      outputs = {
        account_ids = { workload_dev = "222222222222" }
        account_role_arns = {
          workload_dev = "arn:aws:iam::222222222222:role/cross-account"
        }
      }
    }
  }

  override_data {
    target = data.terraform_remote_state.aws_network
    values = {
      outputs = {
        tgw_id        = "tgw-000000000000abcd"
        ipam_pool_ids = { "eu-west-2" = "ipam-pool-eu-west-2-0" }
      }
    }
  }

  override_data {
    target = data.terraform_remote_state.aws_security
    values = {
      outputs = {
        log_archive_bucket_name = "ashes-org-log-archive"
      }
    }
  }

  # With var.log_archive_bucket_name = null, the central bucket name is sourced
  # from the aws-security remote state (its owner), not a hand-typed string.
  assert {
    condition     = data.terraform_remote_state.aws_security[0].outputs.log_archive_bucket_name == "ashes-org-log-archive"
    error_message = "aws_security must expose log_archive_bucket_name for aws-workload to consume"
  }

  # The workload-account role the providers assume is readable from the org contract.
  assert {
    condition     = data.terraform_remote_state.aws_organization[0].outputs.account_role_arns[var.workload_account_key] != ""
    error_message = "aws_organization account_role_arns must expose the workload_account_key role"
  }

  # The shared TGW id is readable from the network contract.
  assert {
    condition     = data.terraform_remote_state.aws_network[0].outputs.tgw_id == "tgw-000000000000abcd"
    error_message = "aws_network tgw_id contract key must be readable by the root"
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

  # The regional IPAM pool for this root's region is readable from the network contract.
  assert {
    condition     = data.terraform_remote_state.aws_network[0].outputs.ipam_pool_ids[local.aws_region] == "ipam-pool-eu-west-2-0"
    error_message = "aws_network ipam_pool_ids must expose a pool for aws_region"
  }
}

# SaaS secret bridge: opt-in, default off; when
# enabled it writes the Supabase connection into an AWS Secrets Manager secret.
run "saas_secret_bridge_default_off" {
  command = plan

  override_data {
    target = data.terraform_remote_state.aws_organization
    values = { outputs = { account_ids = { workload_dev = "222222222222" }, account_role_arns = { workload_dev = "arn:aws:iam::222222222222:role/cross-account" } } }
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
    values = { outputs = { account_ids = { workload_dev = "222222222222" }, account_role_arns = { workload_dev = "arn:aws:iam::222222222222:role/cross-account" } } }
  }
  override_data {
    target = data.terraform_remote_state.aws_network
    values = { outputs = { tgw_id = "tgw-000000000000abcd", ipam_pool_ids = { "eu-west-2" = "ipam-pool-eu-west-2-0" } } }
  }
  override_data {
    target = data.terraform_remote_state.aws_security
    values = { outputs = { log_archive_bucket_name = "ashes-org-log-archive" } }
  }
  override_data {
    target = data.terraform_remote_state.saas[0]
    values = {
      outputs = {
        supabase_api_url           = "https://abcd.supabase.co"
        supabase_service_role_key  = "service-role-key-xxxx"
        supabase_database_password = "db-password-xxxx"
      }
    }
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
    values = { outputs = { account_ids = { workload_dev = "222222222222" }, account_role_arns = { workload_dev = "arn:aws:iam::222222222222:role/cross-account" } } }
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
    values = { outputs = { account_ids = { workload_dev = "222222222222" }, account_role_arns = { workload_dev = "arn:aws:iam::222222222222:role/cross-account" } } }
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
        account_ids = { workload_dev = "222222222222" }
        account_role_arns = {
          workload_dev = "arn:aws:iam::222222222222:role/cross-account"
        }
      }
    }
  }

  override_data {
    target = data.terraform_remote_state.aws_network
    values = {
      outputs = {
        tgw_id        = "tgw-000000000000abcd"
        ipam_pool_ids = { "eu-west-2" = "ipam-pool-eu-west-2-0" }
      }
    }
  }

  override_data {
    target = data.terraform_remote_state.aws_security
    values = {
      outputs = {
        log_archive_bucket_name = "ashes-org-log-archive"
      }
    }
  }

  expect_failures = [var.landing_zone_name]
}
