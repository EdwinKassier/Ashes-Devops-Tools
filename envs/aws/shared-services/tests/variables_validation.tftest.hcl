# Input validation for the aws-shared-services root. Every `validation` block in
# variables.tf gets a rejecting run (expect_failures) plus accepting runs. The
# organization_contract override keeps the aws-organization remote-state read
# out of the plan (count = 0), so no override_data is needed.

mock_provider "aws" {}

variables {
  # Isolate the suite from any committed config/landing-zone.yaml.
  landing_zone_config_path = ""
  landing_zone_name        = "acme"
  organization_contract = {
    organization_id       = "o-abcdefghij"
    management_account_id = "111111111111"
    account_ids           = { shared_services = "777777777777" }
  }
}

# -----------------------------------------------------------------------------
# Accepting runs
# -----------------------------------------------------------------------------

run "accepts_valid_values" {
  command = plan

  variables {
    aws_region      = "us-west-2"
    assume_role_arn = "arn:aws:iam::777777777777:role/OrganizationAccountAccessRole"
    cost_center     = "cc-42"
    owner           = "platform-services"
    default_tags    = { DataClass = "internal" }
  }

  assert {
    condition     = local.aws_region == "us-west-2"
    error_message = "a valid aws_region must be used as-is."
  }

  assert {
    condition     = local.aws_default_tags["Workspace"] == "aws-shared-services" && local.aws_default_tags["CostCenter"] == "cc-42" && local.aws_default_tags["Owner"] == "platform-services" && local.aws_default_tags["DataClass"] == "internal"
    error_message = "valid cost_center / owner / default_tags must reach the provider default_tags."
  }
}

run "accepts_govcloud_assume_role_arn" {
  command = plan

  variables {
    assume_role_arn = "arn:aws-us-gov:iam::777777777777:role/OrganizationAccountAccessRole"
  }
}

run "defaults_apply_when_unset" {
  command = plan

  assert {
    condition     = local.aws_region == "eu-west-2" && local.cost_center == "platform" && local.owner == "platform-team"
    error_message = "unset aws_region / cost_center / owner must fall back to eu-west-2 / platform / platform-team."
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
      account_ids           = { shared_services = "7777777777777" }
    }
  }

  expect_failures = [var.organization_contract]
}

run "rejects_invalid_aws_region" {
  command = plan

  variables {
    aws_region = "eu-west"
  }

  expect_failures = [var.aws_region]
}

run "rejects_non_arn_assume_role" {
  command = plan

  variables {
    assume_role_arn = "OrganizationAccountAccessRole"
  }

  expect_failures = [var.assume_role_arn]
}

run "rejects_user_arn_as_assume_role" {
  command = plan

  variables {
    assume_role_arn = "arn:aws:iam::777777777777:user/operator"
  }

  expect_failures = [var.assume_role_arn]
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

run "rejects_ashes_placeholder_landing_zone_name" {
  command = plan

  variables {
    landing_zone_name = "ashes"
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
