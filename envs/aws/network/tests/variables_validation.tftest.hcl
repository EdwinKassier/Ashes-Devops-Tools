# Input validation for the aws-network root. Every `validation` block in
# variables.tf gets a rejecting run (expect_failures) plus accepting runs. The
# organization_contract override keeps the aws-organization remote-state read
# out of the plan (count = 0), so no override_data is needed.

mock_provider "aws" {}

variables {
  # Isolate the suite from any committed config/landing-zone.yaml.
  landing_zone_config_path = ""
  landing_zone_name        = "acme"
  log_archive_bucket_name  = "acme-org-log-archive"
  organization_contract = {
    organization_id       = "o-abcdefghij"
    management_account_id = "111111111111"
    account_ids           = { network = "666666666666" }
  }
}

# -----------------------------------------------------------------------------
# Accepting runs
# -----------------------------------------------------------------------------

run "accepts_valid_values" {
  command = plan

  variables {
    aws_region          = "eu-west-1"
    aws_enabled_regions = ["eu-west-1", "eu-central-1"]
    top_cidr            = "10.0.0.0/8"
    regional_cidrs      = { eu-west-1 = "10.0.0.0/12", eu-central-1 = "10.16.0.0/12" }
    inspection_cidr     = "10.2.0.0/16"
    egress_cidr         = "10.3.0.0/16"
    availability_zones  = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
    az_count            = 3
    assume_role_arn     = "arn:aws:iam::666666666666:role/OrganizationAccountAccessRole"
    profile             = "starter"
    cost_center         = "networking"
    owner               = "network-team"
    default_tags        = { DataClass = "internal" }
  }

  assert {
    condition     = local.aws_region == "eu-west-1" && join(",", local.aws_enabled_regions) == "eu-west-1,eu-central-1" && local.profile == "starter"
    error_message = "valid aws_region / aws_enabled_regions / profile must be used as-is."
  }

  assert {
    condition     = local.aws_default_tags["Workspace"] == "aws-network" && local.aws_default_tags["CostCenter"] == "networking" && local.aws_default_tags["Owner"] == "network-team" && local.aws_default_tags["DataClass"] == "internal"
    error_message = "valid cost_center / owner / default_tags must reach the provider default_tags."
  }
}

# az_count may equal the number of zones (2 is the minimum: the stage's
# Route 53 Resolver needs private subnets in two AZs).
run "accepts_az_count_equal_to_zone_list" {
  command = plan

  variables {
    availability_zones = ["eu-west-2a", "eu-west-2b"]
    az_count           = 2
    profile            = "production"
  }
}

run "defaults_apply_when_unset" {
  command = plan

  assert {
    condition     = local.aws_region == "eu-west-2" && join(",", local.aws_enabled_regions) == "eu-west-2" && local.profile == "production" && local.cost_center == "platform" && local.owner == "platform-team"
    error_message = "unset region / enabled regions / profile / cost_center / owner must fall back to their built-in defaults."
  }
}

# -----------------------------------------------------------------------------
# Rejecting runs
# -----------------------------------------------------------------------------

run "rejects_non_12_digit_contract_account_id" {
  command = plan

  variables {
    organization_contract = {
      organization_id       = "o-abcdefghij"
      management_account_id = "111111111111"
      account_ids           = { network = "66666666666x" }
    }
  }

  expect_failures = [var.organization_contract]
}

run "rejects_invalid_aws_region" {
  command = plan

  variables {
    aws_region = "eu_west_2"
  }

  expect_failures = [var.aws_region]
}

run "rejects_empty_aws_enabled_regions" {
  command = plan

  variables {
    aws_enabled_regions = []
  }

  expect_failures = [var.aws_enabled_regions]
}

run "rejects_invalid_top_cidr" {
  command = plan

  variables {
    top_cidr = "10.0.0.0"
  }

  expect_failures = [var.top_cidr]
}

run "rejects_invalid_regional_cidr" {
  command = plan

  variables {
    regional_cidrs = { eu-west-2 = "10.0.0.0/12", eu-west-1 = "not-a-cidr" }
  }

  expect_failures = [var.regional_cidrs]
}

run "rejects_invalid_inspection_cidr" {
  command = plan

  variables {
    inspection_cidr = "10.0.0.0/33"
  }

  expect_failures = [var.inspection_cidr]
}

run "rejects_invalid_egress_cidr" {
  command = plan

  variables {
    egress_cidr = "300.1.0.0/16"
  }

  expect_failures = [var.egress_cidr]
}

# (az_count's cross-variable rule is not evaluated once availability_zones
# itself is invalid, so only the zone-list failure is expected.)
run "rejects_empty_availability_zones" {
  command = plan

  variables {
    availability_zones = []
  }

  expect_failures = [var.availability_zones]
}

run "rejects_az_count_zero" {
  command = plan

  variables {
    az_count = 0
  }

  expect_failures = [var.az_count]
}

run "rejects_az_count_above_three" {
  command = plan

  variables {
    availability_zones = ["eu-west-2a", "eu-west-2b", "eu-west-2c", "eu-west-2d"]
    az_count           = 4
  }

  expect_failures = [var.az_count]
}

run "rejects_az_count_exceeding_zone_list" {
  command = plan

  variables {
    availability_zones = ["eu-west-2a", "eu-west-2b"]
    az_count           = 3
  }

  expect_failures = [var.az_count]
}

run "rejects_unset_log_archive_bucket_name" {
  command = plan

  variables {
    log_archive_bucket_name = null
  }

  expect_failures = [var.log_archive_bucket_name]
}

run "rejects_blank_log_archive_bucket_name" {
  command = plan

  variables {
    log_archive_bucket_name = "   "
  }

  expect_failures = [var.log_archive_bucket_name]
}

run "rejects_non_arn_assume_role" {
  command = plan

  variables {
    assume_role_arn = "arn:aws:iam::666666666666:root"
  }

  expect_failures = [var.assume_role_arn]
}

run "rejects_unknown_profile" {
  command = plan

  variables {
    profile = "enterprise"
  }

  expect_failures = [var.profile]
}

run "rejects_uppercase_landing_zone_name" {
  command = plan

  variables {
    landing_zone_name = "Acme"
  }

  expect_failures = [var.landing_zone_name]
}

run "rejects_unset_landing_zone_name" {
  command = plan

  variables {
    landing_zone_name = null
  }

  expect_failures = [var.landing_zone_name]
}

run "rejects_my_org_placeholder_landing_zone_name" {
  command = plan

  variables {
    landing_zone_name = "my-org"
  }

  expect_failures = [var.landing_zone_name]
}

run "rejects_blank_cost_center" {
  command = plan

  variables {
    cost_center = "   "
  }

  expect_failures = [var.cost_center]
}

run "rejects_empty_owner" {
  command = plan

  variables {
    owner = ""
  }

  expect_failures = [var.owner]
}

run "rejects_empty_default_tag_value" {
  command = plan

  variables {
    default_tags = { DataClass = "" }
  }

  expect_failures = [var.default_tags]
}

# One AZ cannot plan (the Route 53 Resolver needs two subnets), so reject it
# at the root with a clear message.
run "az_count_one_rejected" {
  command = plan

  variables {
    az_count = 1
  }

  expect_failures = [var.az_count]
}
