# Input validation for the aws-security root. Every `validation` block in
# variables.tf gets a rejecting run (expect_failures) plus accepting runs. The
# organization_contract override keeps the aws-organization remote-state read
# out of the plan (count = 0), so no override_data is needed.

mock_provider "aws" {}
mock_provider "aws" { alias = "security_tooling" }
mock_provider "aws" { alias = "log_archive" }
mock_provider "aws" { alias = "forensics" }

variables {
  # Isolate the suite from any committed config/landing-zone.yaml.
  landing_zone_config_path = ""
  landing_zone_name        = "acme"
  management_account_id    = "111111111111"
  log_archive_bucket_name  = "acme-org-log-archive"
  # Security Lake off so meta_store_manager_role_arn is not exercised by default.
  enable_security_lake = false
  organization_contract = {
    organization_id       = "o-abcdefghij"
    organization_root_id  = "r-abcd"
    management_account_id = "111111111111"
    account_ids           = { security_tooling = "222222222222", log_archive = "333333333333", shared_services = "444444444444", forensics = "555555555555" }
    account_role_arns     = { security_tooling = "arn:aws:iam::222222222222:role/cross-account", log_archive = "arn:aws:iam::333333333333:role/cross-account", forensics = "arn:aws:iam::555555555555:role/cross-account" }
  }
}

# Under mock providers the forensics CMK ARN is unknown at plan, which makes the
# incident-response count indeterminate; pin it (mirrors root.tftest.hcl).
override_module {
  target  = module.aws_security.module.forensics_cmk
  outputs = { key_arn = "arn:aws:kms:eu-west-2:555555555555:key/forensics-0000" }
}

# -----------------------------------------------------------------------------
# Accepting runs
# -----------------------------------------------------------------------------

run "accepts_valid_values" {
  command = plan

  variables {
    aws_region                = "eu-west-1"
    aws_enabled_regions       = ["eu-west-1", "us-east-1"]
    key_admin_arn             = "arn:aws:iam::111111111111:user/kms-admin"
    kms_key_user_arns         = { log_archive = ["arn:aws:iam::333333333333:role/log-reader"], security_tooling = [] }
    config_role_arn           = "arn:aws:iam::222222222222:role/aws-config-recorder"
    aggregator_role_arn       = "arn:aws:iam::222222222222:role/aws-config-aggregator"
    break_glass_role_arn      = "arn:aws:iam::111111111111:role/OrganizationBreakGlass"
    notification_subscribers  = { soc = { protocol = "https", endpoint = "https://soc.example.com/hook" } }
    enabled_security_services = ["macie", "inspector", "detective", "resource-explorer"]
    cloudtrail_s3_data_events = "all"
    profile                   = "starter"
    cost_center               = "security"
    owner                     = "secops"
    default_tags              = { DataClass = "restricted" }
  }

  assert {
    condition     = local.aws_region == "eu-west-1" && join(",", local.aws_enabled_regions) == "eu-west-1,us-east-1" && local.profile == "starter"
    error_message = "valid aws_region / aws_enabled_regions / profile must be used as-is."
  }

  # An explicit enabled_security_services beats the starter profile default.
  assert {
    condition     = local.enabled_security_services == toset(["macie", "inspector", "detective", "resource-explorer"])
    error_message = "an explicit enabled_security_services must win over the profile default."
  }

  assert {
    condition     = local.aws_default_tags["Workspace"] == "aws-security" && local.aws_default_tags["CostCenter"] == "security" && local.aws_default_tags["Owner"] == "secops" && local.aws_default_tags["DataClass"] == "restricted"
    error_message = "valid cost_center / owner / default_tags must reach the provider default_tags."
  }
}

# Security Lake on with an operator-supplied metastore role ARN.
run "accepts_meta_store_manager_role_arn" {
  command = plan

  variables {
    enable_security_lake        = true
    meta_store_manager_role_arn = "arn:aws:iam::222222222222:role/AmazonSecurityLakeMetaStoreManager"
  }

  assert {
    condition     = local.enable_security_lake == true
    error_message = "enable_security_lake = true must be honoured."
  }
}

run "accepts_each_s3_data_events_mode" {
  command = plan

  variables {
    cloudtrail_s3_data_events = "none"
  }
}

run "defaults_apply_when_unset" {
  command = plan

  assert {
    condition = (
      local.aws_region == "eu-west-2" && join(",", local.aws_enabled_regions) == "eu-west-2" &&
      local.profile == "production" && local.cost_center == "platform" && local.owner == "platform-team"
    )
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
      organization_root_id  = "r-abcd"
      management_account_id = "111111111111"
      account_ids           = { security_tooling = "222222222222", log_archive = "333", shared_services = "444444444444", forensics = "555555555555" }
      account_role_arns     = { security_tooling = "arn:aws:iam::222222222222:role/cross-account", log_archive = "arn:aws:iam::333333333333:role/cross-account", forensics = "arn:aws:iam::555555555555:role/cross-account" }
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
    management_account_id = "1111-1111-1111"
  }

  expect_failures = [var.management_account_id]
}

run "rejects_invalid_aws_region" {
  command = plan

  variables {
    aws_region = "london"
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

run "rejects_group_arn_as_key_admin" {
  command = plan

  variables {
    key_admin_arn = "arn:aws:iam::111111111111:group/kms-admins"
  }

  expect_failures = [var.key_admin_arn]
}

run "rejects_unknown_kms_key_user_key" {
  command = plan

  variables {
    kms_key_user_arns = { audit = ["arn:aws:iam::333333333333:role/log-reader"] }
  }

  expect_failures = [var.kms_key_user_arns]
}

run "rejects_non_arn_config_role" {
  command = plan

  variables {
    config_role_arn = "AWSServiceRoleForConfig"
  }

  expect_failures = [var.config_role_arn]
}

run "rejects_non_arn_aggregator_role" {
  command = plan

  variables {
    aggregator_role_arn = "arn:aws:iam::222222222222:policy/aws-config-aggregator"
  }

  expect_failures = [var.aggregator_role_arn]
}

run "rejects_non_arn_meta_store_manager_role" {
  command = plan

  variables {
    meta_store_manager_role_arn = "AmazonSecurityLakeMetaStoreManager"
  }

  expect_failures = [var.meta_store_manager_role_arn]
}

run "rejects_non_arn_break_glass_role" {
  command = plan

  variables {
    break_glass_role_arn = "arn:aws:iam::role/OrganizationBreakGlass"
  }

  expect_failures = [var.break_glass_role_arn]
}

run "rejects_empty_notification_subscribers" {
  command = plan

  variables {
    notification_subscribers = {}
  }

  expect_failures = [var.notification_subscribers]
}

run "rejects_unknown_security_service" {
  command = plan

  variables {
    enabled_security_services = ["inspector", "guardduty"]
  }

  expect_failures = [var.enabled_security_services]
}

run "rejects_unknown_s3_data_events_mode" {
  command = plan

  variables {
    cloudtrail_s3_data_events = "write-only"
  }

  expect_failures = [var.cloudtrail_s3_data_events]
}

run "rejects_unknown_profile" {
  command = plan

  variables {
    profile = "dev"
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
