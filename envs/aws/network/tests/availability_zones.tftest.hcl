# AZ resolution for the network root (ARC-3). Precedence: availability_zones
# (names) > availability_zone_ids > aws.network.availability_zone_ids > the
# region's first three available zones.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names    = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]
      zone_ids = ["euw2-az2", "euw2-az3", "euw2-az1"]
    }
  }
}

variables {
  landing_zone_config_path = ""
  alarm_subscriber_emails  = ["netops@acme.io"]
  landing_zone_name        = "acme"
  log_archive_bucket_name  = "acme-org-log-archive"
  assume_role_arn          = "arn:aws:iam::666666666666:role/OrganizationAccountAccessRole"
  organization_contract = {
    organization_id       = "o-abc1234567"
    management_account_id = "111111111111"
    account_ids           = { network = "666666666666" }
  }
}

# An eu-west-2 estate on the old defaults (eu-west-2a, eu-west-2b) keeps the
# same zone names, so no subnet is replaced.
run "eu_west_2_defaults_keep_the_old_zone_names" {
  command = plan

  assert {
    condition     = local.availability_zones == tolist(["eu-west-2a", "eu-west-2b", "eu-west-2c"])
    error_message = "With no names or IDs set in eu-west-2, the root must resolve eu-west-2a/b/c."
  }

  assert {
    condition     = module.aws_network_hub.availability_zones == tolist(["eu-west-2a", "eu-west-2b"])
    error_message = "With az_count = 2 the hub VPCs must use eu-west-2a and eu-west-2b, as before."
  }
}

run "region_default_takes_the_first_available_zones" {
  command = plan

  variables {
    aws_region          = "us-east-1"
    aws_enabled_regions = ["us-east-1"]
    regional_cidrs      = { us-east-1 = "10.64.0.0/12" }
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
    regional_cidrs        = { us-east-1 = "10.64.0.0/12" }
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
    condition     = length(data.aws_availability_zones.available) == 0 && local.availability_zones == tolist(["eu-west-2c", "eu-west-2b"])
    error_message = "Explicit availability_zones must win over IDs and skip the data source."
  }
}

run "config_zone_ids_are_read" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-azs.yaml"
  }

  assert {
    condition     = local.availability_zone_ids == tolist(["euw2-az1", "euw2-az3"]) && local.availability_zones == tolist(["eu-west-2c", "eu-west-2b"])
    error_message = "aws.network.availability_zone_ids must map to this account's names."
  }
}

run "variable_zone_ids_beat_config_zone_ids" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-azs.yaml"
    availability_zone_ids    = ["euw2-az2", "euw2-az3"]
  }

  assert {
    condition     = local.availability_zones == tolist(["eu-west-2a", "eu-west-2b"])
    error_message = "var.availability_zone_ids must win over aws.network.availability_zone_ids."
  }
}

run "rejects_malformed_zone_id" {
  command = plan

  variables {
    availability_zone_ids = ["eu-west-2a"]
  }

  expect_failures = [var.availability_zone_ids]
}
