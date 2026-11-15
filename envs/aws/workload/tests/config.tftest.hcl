# Single-source configuration: tfc-admin sets only `environment` on an
# aws-workload-<env> workspace; the workload account key, VPC CIDR and the
# shared org values come from the landing-zone config file.

# The root reads data.aws_availability_zones when no zone names are set (azs.tf).
mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names    = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]
      zone_ids = ["euw2-az2", "euw2-az3", "euw2-az1"]
    }
  }
}
mock_provider "aws" { alias = "us_east_1" }
# tfe serves only the SaaS secret bridge (ephemeral "tfe_outputs"); mocked so
# no run contacts HCP Terraform.
mock_provider "tfe" {}

variables {
  landing_zone_config_path = "tests/fixtures/landing-zone.yaml"
  environment              = "dev"
  kms_key_arn              = "arn:aws:kms:eu-west-2:222222222222:key/abcd-1234"
}

override_data {
  target = data.terraform_remote_state.aws_organization
  values = {
    outputs = {
      contract = {
        organization_id   = "o-abc1234567"
        account_ids       = { workload_nonprod = "222222222222", workload_prod = "333333333333" }
        account_role_arns = { workload_nonprod = "arn:aws:iam::222222222222:role/cross-account", workload_prod = "arn:aws:iam::333333333333:role/cross-account" }
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
        log_archive_bucket_name = "cfgco-org-log-archive"
      }
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
    condition     = local.workload_account_key == "workload_prod" && local.vpc_cidr == "10.72.0.0/16"
    error_message = "an environment without vpc_cidr in the config must get the built-in 10.72.0.0/16."
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

# Scaffold matrix: committed scaffolder output (make scaffold-fixtures) must plan.
run "scaffold_aws_plans" {
  command = plan

  variables {
    landing_zone_config_path = "../../../tests/fixtures/scaffold/landing-zone.aws.yaml"
    environment              = "dev"
  }

  # The scaffold names its workload accounts workload_dev / workload_prod.
  override_data {
    target = data.terraform_remote_state.aws_organization
    values = {
      outputs = {
        contract = {
          organization_id   = "o-abc1234567"
          account_ids       = { workload_dev = "222222222222", workload_prod = "333333333333" }
          account_role_arns = { workload_dev = "arn:aws:iam::222222222222:role/cross-account", workload_prod = "arn:aws:iam::333333333333:role/cross-account" }
        }
      }
    }
  }
}

run "scaffold_gcp_aws_plans" {
  command = plan

  variables {
    landing_zone_config_path = "../../../tests/fixtures/scaffold/landing-zone.gcp-aws.yaml"
    environment              = "dev"
  }

  # The scaffold names its workload accounts workload_dev / workload_prod.
  override_data {
    target = data.terraform_remote_state.aws_organization
    values = {
      outputs = {
        contract = {
          organization_id   = "o-abc1234567"
          account_ids       = { workload_dev = "222222222222", workload_prod = "333333333333" }
          account_role_arns = { workload_dev = "arn:aws:iam::222222222222:role/cross-account", workload_prod = "arn:aws:iam::333333333333:role/cross-account" }
        }
      }
    }
  }
}

run "scaffold_gcp_aws_saas_plans" {
  command = plan

  variables {
    landing_zone_config_path = "../../../tests/fixtures/scaffold/landing-zone.gcp-aws-saas.yaml"
    environment              = "dev"
  }

  # The scaffold names its workload accounts workload_dev / workload_prod.
  override_data {
    target = data.terraform_remote_state.aws_organization
    values = {
      outputs = {
        contract = {
          organization_id   = "o-abc1234567"
          account_ids       = { workload_dev = "222222222222", workload_prod = "333333333333" }
          account_role_arns = { workload_dev = "arn:aws:iam::222222222222:role/cross-account", workload_prod = "arn:aws:iam::333333333333:role/cross-account" }
        }
      }
    }
  }
}

# ARC-16: production comes from is_production, never from the environment name.
run "is_production_from_config" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.services.yaml"
    environment              = "prod"
  }

  assert {
    condition     = local.is_production == true
    error_message = "aws.workload_environments.prod.is_production: true must make the root production."
  }
}

run "dev_config_is_not_production" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.services.yaml"
  }

  assert {
    condition     = local.is_production == false
    error_message = "aws.workload_environments.dev.is_production: false must leave the root non-production."
  }
}

run "is_production_variable_wins_over_config" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.services.yaml"
    is_production            = true
  }

  assert {
    condition     = local.is_production == true
    error_message = "An explicit is_production variable must win over the config file."
  }
}

# DataClassification default tag (CMP-10): aws.workload_environments.<env>
# .data_classification, else internal; an explicit variable wins; any value
# outside the tag policy's four is rejected.
run "data_classification_tag_from_config" {
  command = plan

  variables {
    environment = "prod"
  }

  assert {
    condition     = local.aws_default_tags["DataClassification"] == "restricted"
    error_message = "the DataClassification default tag must come from aws.workload_environments.<env>.data_classification."
  }
}

run "data_classification_tag_defaults_to_internal" {
  command = plan

  assert {
    condition     = local.aws_default_tags["DataClassification"] == "internal"
    error_message = "an environment without data_classification must be tagged DataClassification = internal."
  }
}

run "data_classification_variable_wins" {
  command = plan

  variables {
    data_classification = "confidential"
  }

  assert {
    condition     = local.aws_default_tags["DataClassification"] == "confidential"
    error_message = "an explicit data_classification must win over the config file."
  }
}

run "data_classification_rejects_unknown_value" {
  command = plan

  variables {
    data_classification = "secret"
  }

  expect_failures = [var.data_classification]
}
