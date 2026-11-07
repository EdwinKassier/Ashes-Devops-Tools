# Input validation for the aws-backup root. Every `validation` block in
# variables.tf gets a rejecting run (expect_failures) plus accepting runs. The
# organization_contract override keeps the aws-organization remote-state read
# out of the plan (count = 0), so no override_data is needed.

mock_provider "aws" {}
mock_provider "aws" { alias = "backup" }

variables {
  # Isolate the suite from any committed config/landing-zone.yaml.
  landing_zone_config_path = ""
  landing_zone_name        = "acme"
  management_account_id    = "111111111111"
  organization_contract = {
    account_ids       = { backup = "444444444444" }
    account_role_arns = { backup = "arn:aws:iam::444444444444:role/cross-account" }
    ou_ids            = { Workloads = "ou-abcd-workloads0" }
  }
}

# -----------------------------------------------------------------------------
# Accepting runs
# -----------------------------------------------------------------------------

run "accepts_valid_values" {
  command = plan

  variables {
    aws_region               = "us-east-1"
    changeable_for_days      = 3
    backup_role_arn          = "arn:aws:iam::$account:role/aws-backup-org-role"
    restore_testing_role_arn = "arn:aws:iam::444444444444:role/restore-testing"
    cost_center              = "cc-42"
    owner                    = "backup-team"
    default_tags             = { DataClass = "internal" }
  }

  assert {
    condition     = local.aws_region == "us-east-1" && local.management_account_id == "111111111111"
    error_message = "valid aws_region / management_account_id must be used as-is."
  }

  assert {
    condition     = local.aws_default_tags["CostCenter"] == "cc-42" && local.aws_default_tags["Owner"] == "backup-team" && local.aws_default_tags["DataClass"] == "internal"
    error_message = "valid cost_center / owner / default_tags must reach the provider default_tags."
  }
}

run "accepts_govcloud_partition_and_fixed_account_backup_role" {
  command = plan

  variables {
    backup_role_arn = "arn:aws-us-gov:iam::444444444444:role/aws-backup-org-role"
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
      account_ids       = { backup = "4444" }
      account_role_arns = { backup = "arn:aws:iam::444444444444:role/cross-account" }
      ou_ids            = { Workloads = "ou-abcd-workloads0" }
    }
  }

  expect_failures = [var.organization_contract]
}

run "rejects_unset_management_account_id" {
  command = plan

  variables {
    management_account_id = null
  }

  expect_failures = [var.management_account_id]
}

run "rejects_malformed_management_account_id" {
  command = plan

  variables {
    management_account_id = "11111111111a"
  }

  expect_failures = [var.management_account_id]
}

run "rejects_invalid_aws_region" {
  command = plan

  variables {
    aws_region = "europe-west2"
  }

  expect_failures = [var.aws_region]
}

run "rejects_changeable_for_days_below_three" {
  command = plan

  variables {
    changeable_for_days = 2
  }

  expect_failures = [var.changeable_for_days]
}

run "rejects_non_arn_backup_role" {
  command = plan

  variables {
    backup_role_arn = "aws-backup-org-role"
  }

  expect_failures = [var.backup_role_arn]
}

run "rejects_backup_role_with_bad_account" {
  command = plan

  variables {
    backup_role_arn = "arn:aws:iam::4444:role/aws-backup-org-role"
  }

  expect_failures = [var.backup_role_arn]
}

# The restore-testing role lives in the backup account: no $account templating.
run "rejects_templated_restore_testing_role" {
  command = plan

  variables {
    restore_testing_role_arn = "arn:aws:iam::$account:role/restore-testing"
  }

  expect_failures = [var.restore_testing_role_arn]
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

# A contract without the Workloads OU fails on the named guard (the backup
# policy attaches there), not on a bare lookup.
run "organization_contract_without_workloads_ou_fails" {
  command = plan

  variables {
    organization_contract = {
      account_ids       = { backup = "444444444444" }
      account_role_arns = { backup = "arn:aws:iam::444444444444:role/cross-account" }
      ou_ids            = { Security = "ou-abcd-security00" }
    }
  }

  expect_failures = [terraform_data.organization_contract_guard]
}
