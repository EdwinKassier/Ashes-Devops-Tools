# Variable-validation tests for the aws-backup stage.
#
# Uses two mock providers so no AWS credentials are required. The accept case
# reaches (and passes) plan with the module defaults plus the three required
# ARNs/OU id; the reject case fails the changeable_for_days validation (WORM
# cooling-off minimum) before any resource is evaluated.

mock_provider "aws" {}
mock_provider "aws" { alias = "backup" }

variables {
  restore_testing_role_arn = "arn:aws:iam::444444444444:role/backup-restore-test"
  backup_role_arn          = "arn:aws:iam::111111111111:role/aws-backup-role"
  workloads_ou_id          = "ou-abcd-11111111"
}

run "defaults_accepted" {
  # Accept case: the defaults (org-backup-vault, 7/3650/3, eu-west-2) plus the
  # required ARNs/OU id must pass all validations and plan.
  command = plan
}

run "invalid_changeable_for_days_rejected" {
  # Reject case: a sub-3 cooling-off window must fail the Compliance-mode
  # Vault Lock validation.
  command = plan

  variables {
    changeable_for_days = 2
  }

  expect_failures = [var.changeable_for_days]
}

run "backup_role_arn_accepts_account_variable" {
  command = plan

  variables {
    backup_role_arn = "arn:aws:iam::$account:role/my-backup-role"
  }
}

run "malformed_backup_role_arn_rejected" {
  command = plan

  variables {
    backup_role_arn = "my-backup-role"
  }

  expect_failures = [var.backup_role_arn]
}

run "central_copy_needs_organization_and_backup_account" {
  command = plan

  variables {
    workloads_ou_id     = "ou-abcd-11111111"
    enable_central_copy = true
  }

  expect_failures = [var.enable_central_copy]
}

run "central_copy_rejects_legacy_stack_set" {
  command = plan

  variables {
    workloads_ou_id              = "ou-abcd-11111111"
    enable_central_copy          = true
    organization_id              = "o-abc1234567"
    backup_account_id            = "444444444444"
    copy_vault_kms_key_arn       = "arn:aws:kms:eu-west-2:444444444444:key/11111111-2222-3333-4444-555555555555"
    create_backup_role_stack_set = true
  }

  expect_failures = [var.enable_central_copy]
}

run "copy_retention_below_vault_lock_minimum_rejected" {
  command = plan

  variables {
    workloads_ou_id        = "ou-abcd-11111111"
    enable_central_copy    = true
    organization_id        = "o-abc1234567"
    backup_account_id      = "444444444444"
    copy_vault_kms_key_arn = "arn:aws:kms:eu-west-2:444444444444:key/11111111-2222-3333-4444-555555555555"
    copy_retention_days    = 3
  }

  expect_failures = [var.copy_retention_days]
}

run "dr_region_equal_to_home_region_rejected" {
  command = plan

  variables {
    workloads_ou_id = "ou-abcd-11111111"
    dr_region       = "eu-west-2"
  }

  expect_failures = [var.dr_region]
}

# The copy vault publishes failed backup, copy and restore events to
# copy_vault_notification_topic_arn. Planned without overriding the copy vault
# module so its notification_topic_arn output comes from the planned resource.
run "copy_vault_notification_topic_wired" {
  command = plan

  variables {
    enable_central_copy               = true
    organization_id                   = "o-abc1234567"
    backup_account_id                 = "444444444444"
    copy_vault_kms_key_arn            = "arn:aws:kms:eu-west-2:444444444444:key/11111111-2222-3333-4444-555555555555"
    copy_vault_notification_topic_arn = "arn:aws:sns:eu-west-2:444444444444:backup-events"
  }

  assert {
    condition     = module.copy_vault[0].notification_topic_arn == "arn:aws:sns:eu-west-2:444444444444:backup-events"
    error_message = "copy_vault_notification_topic_arn must reach the copy vault's notifications."
  }
}

run "malformed_copy_vault_notification_topic_arn_rejected" {
  command = plan

  variables {
    copy_vault_notification_topic_arn = "backup-events"
  }

  expect_failures = [var.copy_vault_notification_topic_arn]
}
