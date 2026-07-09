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
