# Variable-validation tests for the aws-security stage.
#
# Uses five mock providers so no AWS credentials are required. The accept case
# reaches (and passes) plan with a valid var set; the reject case fails the
# management_account_id validation before any resource is evaluated.

mock_provider "aws" {}
mock_provider "aws" { alias = "management" }
mock_provider "aws" { alias = "security_tooling" }
mock_provider "aws" { alias = "log_archive" }
mock_provider "aws" { alias = "forensics" }

variables {
  org_id                      = "o-abc1234567"
  org_root_id                 = "r-abc1"
  management_account_id       = "111111111111"
  security_tooling_account_id = "222222222222"
  log_archive_account_id      = "333333333333"
  shared_services_account_id  = "555555555555"
  forensics_account_id        = "444444444444"
  aws = {
    log_archive_bucket_name     = "ashes-org-log-archive"
    key_admin_arn               = "arn:aws:iam::333333333333:role/kms-admin"
    config_role_arn             = "arn:aws:iam::222222222222:role/aws-config-role"
    aggregator_role_arn         = "arn:aws:iam::222222222222:role/aws-config-aggregator"
    meta_store_manager_role_arn = "arn:aws:iam::222222222222:role/AmazonSecurityLakeMetaStoreManager"
    break_glass_role_arn        = "arn:aws:iam::111111111111:role/break-glass"
    notification_subscribers = {
      secops = { protocol = "email", endpoint = "secops@example.com" }
    }
  }
}

# The forensics CMK ARN flows into the incident-response module's
# forensics_kms_key_arn, whose count keys off whether that ARN is set. Under
# mock the CMK ARN is unknown at plan, which would make that count
# indeterminate; override the CMK output with a known ARN so plan can resolve.
override_module {
  target  = module.forensics_cmk
  outputs = { key_arn = "arn:aws:kms:eu-west-2:444444444444:key/forensics-0000" }
}

run "valid_var_set_accepted" {
  # Accept case: a complete, valid var set must pass all validations and plan.
  command = plan
}

run "invalid_management_account_id_rejected" {
  # Reject case: a malformed (non-12-digit) management account ID must fail its
  # validation.
  command = plan

  variables {
    management_account_id = "not-an-account"
  }

  expect_failures = [var.management_account_id]
}

run "create_break_glass_without_principals_rejected" {
  command = plan

  variables {
    aws = merge(var.aws, {
      create_break_glass             = true
      break_glass_trusted_principals = []
    })
  }

  expect_failures = [var.aws]
}

run "unknown_kms_key_user_target_rejected" {
  # Reject case: kms_key_user_arns may only target the three stage CMKs.
  command = plan

  variables {
    aws = merge(var.aws, {
      kms_key_user_arns = { audit = ["arn:aws:iam::333333333333:role/LogReader"] }
    })
  }

  expect_failures = [var.aws]
}

run "invalid_cloudtrail_s3_data_events_rejected" {
  command = plan

  variables {
    aws = merge(var.aws, {
      cloudtrail_s3_data_events = "objects"
    })
  }

  expect_failures = [var.aws]
}

run "rejects_malformed_key_admin_arn" {
  command = plan

  variables {
    aws = merge(var.aws, {
      key_admin_arn = "kms-admin"
    })
  }

  expect_failures = [var.aws]
}

run "rejects_wildcard_key_policy_admin_role_name" {
  command = plan

  variables {
    key_policy_admin_role_name = "break-*"
  }

  expect_failures = [var.key_policy_admin_role_name]
}

# Validations the aws-security root used to run on its own variables; they now
# live on the stage's aws object (aws_overrides in the root feeds it).

run "rejects_empty_aws_enabled_regions" {
  command = plan

  variables {
    aws = merge(var.aws, {
      aws_enabled_regions = []
    })
  }

  expect_failures = [var.aws]
}

run "rejects_unset_log_archive_bucket_name" {
  command = plan

  variables {
    aws = merge(var.aws, {
      log_archive_bucket_name = null
    })
  }

  expect_failures = [var.aws]
}

run "rejects_blank_log_archive_bucket_name" {
  command = plan

  variables {
    aws = merge(var.aws, {
      log_archive_bucket_name = "   "
    })
  }

  expect_failures = [var.aws]
}

run "rejects_group_arn_as_key_admin" {
  command = plan

  variables {
    aws = merge(var.aws, {
      key_admin_arn = "arn:aws:iam::111111111111:group/kms-admins"
    })
  }

  expect_failures = [var.aws]
}

run "rejects_non_arn_config_role" {
  command = plan

  variables {
    aws = merge(var.aws, {
      config_role_arn = "AWSServiceRoleForConfig"
    })
  }

  expect_failures = [var.aws]
}

run "rejects_non_arn_aggregator_role" {
  command = plan

  variables {
    aws = merge(var.aws, {
      aggregator_role_arn = "arn:aws:iam::222222222222:policy/aws-config-aggregator"
    })
  }

  expect_failures = [var.aws]
}

run "rejects_non_arn_meta_store_manager_role" {
  command = plan

  variables {
    aws = merge(var.aws, {
      meta_store_manager_role_arn = "AmazonSecurityLakeMetaStoreManager"
    })
  }

  expect_failures = [var.aws]
}

run "rejects_non_arn_break_glass_role" {
  command = plan

  variables {
    aws = merge(var.aws, {
      break_glass_role_arn = "arn:aws:iam::role/OrganizationBreakGlass"
    })
  }

  expect_failures = [var.aws]
}

run "rejects_empty_notification_subscribers" {
  command = plan

  variables {
    aws = merge(var.aws, {
      notification_subscribers = {}
    })
  }

  expect_failures = [var.aws]
}

run "rejects_unknown_security_service" {
  command = plan

  variables {
    aws = merge(var.aws, {
      enabled_security_services = ["inspector", "guardduty"]
    })
  }

  expect_failures = [var.aws]
}

run "delegated_admin_trail_name_must_differ" {
  command = plan

  variables {
    aws = merge(var.aws, { cloudtrail_delegated_admin_trail_name = "org-trail" })
  }

  expect_failures = [var.aws]
}

run "delegated_admin_needs_organization_trail" {
  command = plan

  variables {
    aws = merge(var.aws, { enable_cloudtrail_delegated_admin = true, create_organization_trail = false })
  }

  expect_failures = [var.aws]
}
