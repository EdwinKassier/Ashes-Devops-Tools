# AZ resolution for the workload root (ARC-3). Precedence: availability_zones
# (names) > availability_zone_ids > aws.workload_environments.<env>.availability_zone_ids
# > aws.network.availability_zone_ids > the region's first three available
# zones. Standalone (enable_network_hub = false) keeps the aws-network read out
# of the plan.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names    = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]
      zone_ids = ["euw2-az2", "euw2-az3", "euw2-az1"]
    }
  }
}
mock_provider "aws" { alias = "us_east_1" }
mock_provider "tfe" {}

variables {
  landing_zone_config_path = ""
  landing_zone_name        = "acme"
  workload_account_key     = "workload_dev"
  kms_key_arn              = "arn:aws:kms:eu-west-2:222222222222:key/abcd-1234"
  enable_network_hub       = false

  organization_contract = { account_ids = { workload_dev = "222222222222" } }
  security_contract     = { log_archive_bucket_name = "acme-org-log-archive" }
}

# An eu-west-2 workload on the old stage default (eu-west-2a, eu-west-2b)
# keeps the same zone names, so no subnet is replaced.
run "eu_west_2_defaults_keep_the_old_zone_names" {
  command = plan

  assert {
    condition     = module.aws_workload.availability_zones == tolist(["eu-west-2a", "eu-west-2b"])
    error_message = "With no names or IDs set in eu-west-2 and az_count = 2, the spoke must use eu-west-2a and eu-west-2b, as before."
  }
}

run "region_default_takes_the_first_available_zones" {
  command = plan

  variables {
    aws_region          = "us-east-1"
    aws_enabled_regions = ["us-east-1"]
  }

  override_data {
    target = data.aws_availability_zones.available
    values = {
      names    = ["us-east-1d", "us-east-1a", "us-east-1c", "us-east-1b"]
      zone_ids = ["use1-az2", "use1-az4", "use1-az1", "use1-az6"]
    }
  }

  assert {
    condition     = local.availability_zones == tolist(["us-east-1a", "us-east-1b", "us-east-1c"])
    error_message = "With no names or IDs set, the root must use the region's first three available zones (sorted), not eu-west-2."
  }
}

run "zone_ids_map_to_this_accounts_names" {
  command = plan

  variables {
    aws_region            = "us-east-1"
    aws_enabled_regions   = ["us-east-1"]
    availability_zone_ids = ["use1-az1", "use1-az4"]
  }

  override_data {
    target = data.aws_availability_zones.available
    values = {
      names    = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d"]
      zone_ids = ["use1-az4", "use1-az6", "use1-az1", "use1-az2"]
    }
  }

  assert {
    condition     = local.availability_zones == tolist(["us-east-1c", "us-east-1a"])
    error_message = "AZ IDs must map to this account's zone names, in the given order."
  }
}

run "unknown_zone_id_fails_the_plan" {
  command = plan

  variables {
    availability_zone_ids = ["euw2-az9", "euw2-az2"]
  }

  expect_failures = [data.aws_availability_zones.available]
}

run "az_count_above_the_resolved_zones_fails_the_plan" {
  command = plan

  variables {
    availability_zone_ids = ["euw2-az2", "euw2-az3"]
    az_count              = 3
  }

  expect_failures = [data.aws_availability_zones.available]
}

run "explicit_names_skip_the_lookup" {
  command = plan

  variables {
    availability_zones    = ["eu-west-2c", "eu-west-2b"]
    availability_zone_ids = ["euw2-az2", "euw2-az3"]
  }

  assert {
    condition     = length(data.aws_availability_zones.available) == 0 && module.aws_workload.availability_zones == tolist(["eu-west-2c", "eu-west-2b"])
    error_message = "Explicit availability_zones must win over IDs, skip the data source and reach the spoke."
  }
}

run "az_count_reaches_the_spoke" {
  command = plan

  variables {
    az_count = 3
  }

  assert {
    condition     = module.aws_workload.availability_zones == tolist(["eu-west-2a", "eu-west-2b", "eu-west-2c"])
    error_message = "az_count must reach the workload stage."
  }
}

run "environment_zone_ids_win_over_network_zone_ids" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-azs.yaml"
    environment              = "dev"
  }

  override_data {
    target = data.aws_availability_zones.available
    values = {
      names    = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d"]
      zone_ids = ["use1-az4", "use1-az6", "use1-az1", "use1-az2"]
    }
  }

  assert {
    condition     = local.availability_zone_ids == tolist(["use1-az6", "use1-az4"]) && local.availability_zones == tolist(["us-east-1b", "us-east-1a"])
    error_message = "aws.workload_environments.<env>.availability_zone_ids must win over aws.network.availability_zone_ids."
  }
}

run "network_zone_ids_apply_when_the_environment_sets_none" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-azs.yaml"
    workload_account_key     = "workload_prod"
    environment              = "prod"
    organization_contract    = { account_ids = { workload_prod = "333333333333" } }
  }

  override_data {
    target = data.aws_availability_zones.available
    values = {
      names    = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d"]
      zone_ids = ["use1-az4", "use1-az6", "use1-az1", "use1-az2"]
    }
  }

  assert {
    condition     = local.availability_zone_ids == tolist(["use1-az1", "use1-az4"]) && local.availability_zones == tolist(["us-east-1c", "us-east-1a"])
    error_message = "With no per-environment IDs, the workload must use aws.network.availability_zone_ids (the hub's zones)."
  }
}

run "rejects_malformed_zone_id" {
  command = plan

  variables {
    availability_zone_ids = ["eu-west-2a"]
  }

  expect_failures = [var.availability_zone_ids]
}

run "rejects_az_count_above_three" {
  command = plan

  variables {
    az_count = 4
  }

  expect_failures = [var.az_count]
}
