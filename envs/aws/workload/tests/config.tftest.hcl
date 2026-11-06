# Single-source configuration: tfc-admin sets only `environment` on an
# aws-workload-<env> workspace; the workload account key, VPC CIDR and the
# shared org values come from the landing-zone config file.

mock_provider "aws" {}
mock_provider "aws" { alias = "us_east_1" }

variables {
  landing_zone_config_path = "tests/fixtures/landing-zone.yaml"
  environment              = "dev"
  config_role_arn          = "arn:aws:iam::222222222222:role/config-recorder"
  kms_key_arn              = "arn:aws:kms:eu-west-2:222222222222:key/abcd-1234"
}

override_data {
  target = data.terraform_remote_state.aws_organization
  values = {
    outputs = {
      account_ids       = { workload_nonprod = "222222222222", workload_prod = "333333333333" }
      account_role_arns = { workload_nonprod = "arn:aws:iam::222222222222:role/cross-account", workload_prod = "arn:aws:iam::333333333333:role/cross-account" }
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
      log_archive_bucket_name = "cfgco-org-log-archive"
    }
  }
}

run "workload_values_come_from_config_file" {
  command = plan

  assert {
    condition     = local.workload_account_key == "workload_nonprod" && local.vpc_cidr == "10.40.0.0/16" && local.environment == "dev"
    error_message = "workload_account_key / vpc_cidr must come from aws.workload_environments[environment]."
  }

  assert {
    condition     = local.landing_zone_name == "cfgco" && local.tfc_organization == "cfg-tfc" && join(",", local.aws_enabled_regions) == "eu-west-2,eu-west-1"
    error_message = "landing_zone_name / tfc_organization / aws_enabled_regions must come from the config file."
  }
}

run "vpc_cidr_defaults_when_not_in_config" {
  command = plan

  variables {
    environment = "prod"
  }

  assert {
    condition     = local.workload_account_key == "workload_prod" && local.vpc_cidr == "10.20.0.0/16"
    error_message = "an environment without vpc_cidr in the config must get the built-in 10.20.0.0/16."
  }
}

run "unknown_environment_fails" {
  command = plan

  variables {
    environment = "qa"
  }

  expect_failures = [var.workload_account_key]
}

run "services_from_config" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.services.yaml"
  }

  assert {
    condition     = join(",", sort(keys(local.services))) == "api,worker" && local.services["api"].cpu == 512 && local.apps_enabled
    error_message = "aws.workload_environments.dev.services must populate the services."
  }
}

run "empty_services_section_is_noop" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.services.yaml"
    environment              = "prod"
  }

  assert {
    condition     = length(local.services) == 0 && !local.apps_enabled
    error_message = "an empty services section must create nothing."
  }
}

run "variable_overrides_config" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.services.yaml"
    services                 = { only = {} }
  }

  assert {
    condition     = join(",", keys(local.services)) == "only"
    error_message = "an explicit services variable must win over the config file."
  }
}
