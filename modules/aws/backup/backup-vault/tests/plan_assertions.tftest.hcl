# Resource-assertion tests for the aws/backup-vault module.
#
# Asserts on configured attributes that are known at plan time under
# mock_provider. Provider-computed attributes (arns, ids) are not asserted on.

mock_provider "aws" {}

run "vault_lock_and_restore_testing_configured" {
  command = plan

  variables {
    restore_testing_role_arn = "arn:aws:iam::123456789012:role/BackupRestoreTestRole"
  }

  assert {
    condition     = aws_backup_vault_lock_configuration.this.min_retention_days == var.min_retention_days
    error_message = "Vault Lock min_retention_days must match the configured variable"
  }

  assert {
    condition     = aws_backup_vault_lock_configuration.this.changeable_for_days == var.changeable_for_days
    error_message = "Vault Lock must be in Compliance mode (changeable_for_days set)"
  }

  assert {
    condition     = aws_backup_restore_testing_plan.this[0].name == var.restore_testing_plan_name
    error_message = "A restore testing plan with the configured name must exist"
  }

  assert {
    condition     = aws_backup_restore_testing_selection.this["EBS"].protected_resource_type == "EBS"
    error_message = "Restore testing selection must target EBS recovery points"
  }
}

# No restore_testing_role_arn: the module creates the restore-testing service
# role (trusted by backup.amazonaws.com, AWSBackupServiceRolePolicyForRestores).
run "restore_testing_role_created_by_default" {
  command = plan

  assert {
    condition     = length(aws_iam_role.restore_testing) == 1 && jsondecode(aws_iam_role.restore_testing[0].assume_role_policy).Statement[0].Principal.Service == "backup.amazonaws.com"
    error_message = "With restore_testing_role_arn = null a backup.amazonaws.com-trusted role must be created."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.restore_testing[0].policy_arn == "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
    error_message = "The created role must carry AWSBackupServiceRolePolicyForRestores."
  }
}

run "explicit_restore_testing_role_creates_nothing" {
  command = plan

  variables {
    restore_testing_role_arn = "arn:aws:iam::123456789012:role/BackupRestoreTestRole"
  }

  assert {
    condition     = length(aws_iam_role.restore_testing) == 0 && aws_backup_restore_testing_selection.this["EBS"].iam_role_arn == "arn:aws:iam::123456789012:role/BackupRestoreTestRole"
    error_message = "An explicit restore_testing_role_arn must be used as-is and no role created."
  }
}

# Boundary propagation (tfc-oidc-baseline): the restore-testing role carries
# permissions_boundary_arn so a member-account tfc-apply role may create it.
run "restore_testing_role_permissions_boundary" {
  command = plan

  variables {
    permissions_boundary_arn = "arn:aws:iam::123456789012:policy/tfc-apply-boundary"
  }

  assert {
    condition     = aws_iam_role.restore_testing[0].permissions_boundary == "arn:aws:iam::123456789012:policy/tfc-apply-boundary"
    error_message = "The restore-testing role must carry permissions_boundary_arn."
  }
}

run "module_tags_applied" {
  command = plan

  variables {
    restore_testing_role_arn = "arn:aws:iam::123456789012:role/BackupRestoreTestRole"
    tags                     = { Owner = "test" }
  }

  assert {
    condition     = aws_backup_vault.this.tags["Owner"] == "test"
    error_message = "module-level tags must land on aws_backup_vault.this"
  }
}

# The default keeps today's single EBS selection, with its existing name, so an
# existing estate's selection moves in state (moved block) instead of being
# replaced.
run "default_ebs_selection_keeps_its_name" {
  command = plan

  assert {
    condition = (
      toset(keys(aws_backup_restore_testing_selection.this)) == toset(["EBS"]) &&
      aws_backup_restore_testing_selection.this["EBS"].name == "ebs_restore_test" &&
      aws_backup_restore_testing_selection.this["EBS"].protected_resource_conditions[0].string_equals[0].key == "aws:ResourceTag/backup"
    )
    error_message = "the default selection must stay the tag-selected EBS selection named ebs_restore_test."
  }

  assert {
    condition     = length(aws_backup_vault_policy.copy_in) == 0
    error_message = "no vault access policy unless allow_copy_from_organization_id is set."
  }
}

run "copy_in_policy_and_restore_types" {
  command = plan

  variables {
    vault_name                      = "org-backup-copy-vault"
    allow_copy_from_organization_id = "o-abc1234567"
    restore_testing_resource_types  = ["EBS", "Aurora", "RDS", "S3", "DynamoDB", "EFS"]
    restore_testing_plan_name       = "org_restore_test_copy"
    kms_key_arn                     = "arn:aws:kms:eu-west-2:444444444444:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition     = aws_backup_vault.this.kms_key_arn == "arn:aws:kms:eu-west-2:444444444444:key/11111111-2222-3333-4444-555555555555"
    error_message = "the vault must be encrypted with the caller's customer managed key."
  }

  assert {
    condition = (
      jsondecode(aws_backup_vault_policy.copy_in[0].policy).Statement[0].Action == "backup:CopyIntoBackupVault" &&
      jsondecode(aws_backup_vault_policy.copy_in[0].policy).Statement[0].Condition.StringEquals["aws:PrincipalOrgID"] == "o-abc1234567"
    )
    error_message = "the copy vault must accept CopyIntoBackupVault from the organization only."
  }

  assert {
    condition     = toset(keys(aws_backup_restore_testing_selection.this)) == toset(["EBS", "Aurora", "RDS", "S3", "DynamoDB", "EFS"])
    error_message = "restore testing must select every listed resource type, not only EBS."
  }

  assert {
    condition     = aws_backup_restore_testing_selection.this["Aurora"].protected_resource_arns == toset(["*"]) && aws_backup_restore_testing_selection.this["Aurora"].name == "ebs_restore_test_aurora"
    error_message = "non-EBS restore selections must select all protected resources of the type in the vault."
  }
}

run "no_restore_testing_when_disabled" {
  command = plan

  variables {
    create_restore_testing = false
  }

  assert {
    condition     = length(aws_backup_restore_testing_plan.this) == 0 && length(aws_backup_restore_testing_selection.this) == 0 && length(aws_iam_role.restore_testing) == 0
    error_message = "create_restore_testing = false must drop the plan, the selections and the created role."
  }

  assert {
    condition     = output.restore_testing_plan_arn == null && output.restore_testing_role_arn == null
    error_message = "with restore testing off the restore-testing outputs must be null."
  }
}
