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
    condition     = aws_backup_restore_testing_plan.this.name == var.restore_testing_plan_name
    error_message = "A restore testing plan with the configured name must exist"
  }

  assert {
    condition     = aws_backup_restore_testing_selection.this.protected_resource_type == "EBS"
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
    condition     = length(aws_iam_role.restore_testing) == 0 && aws_backup_restore_testing_selection.this.iam_role_arn == "arn:aws:iam::123456789012:role/BackupRestoreTestRole"
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
