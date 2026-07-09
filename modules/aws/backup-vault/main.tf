# KMS-encrypted AWS Backup vault with Compliance-mode Vault Lock and restore
# testing for the SRA landing zone. Runs in the delegated Backup account.
#
# The vault is the WORM target for the organization backup plan. Vault Lock is
# configured in Compliance mode (changeable_for_days is non-null): once the
# cooling-off window elapses the lock is immutable and recovery points cannot be
# deleted before min_retention_days by anyone, including the root user. This is
# the control that makes backups tamper-proof against ransomware / rogue admins.
#
# Restore testing (aws_backup_restore_testing_plan + _selection) periodically
# restores recovery points on a schedule so recoverability is continuously
# validated rather than assumed. The selection targets EBS recovery points by a
# tag condition so the plan is apply-ready without hard-coding resource ARNs.

resource "aws_backup_vault" "this" {
  name        = var.vault_name
  kms_key_arn = var.kms_key_arn != "" ? var.kms_key_arn : null
}

resource "aws_backup_vault_lock_configuration" "this" {
  backup_vault_name = aws_backup_vault.this.name

  # A non-null changeable_for_days puts the lock in Compliance mode (WORM):
  # the configuration can only be changed/deleted during this cooling-off window.
  changeable_for_days = var.changeable_for_days
  min_retention_days  = var.min_retention_days
  max_retention_days  = var.max_retention_days
}

resource "aws_backup_restore_testing_plan" "this" {
  name                = var.restore_testing_plan_name
  schedule_expression = var.restore_testing_schedule
  start_window_hours  = var.start_window_hours

  recovery_point_selection {
    algorithm             = "LATEST_WITHIN_WINDOW"
    include_vaults        = [aws_backup_vault.this.arn]
    recovery_point_types  = ["SNAPSHOT"]
    selection_window_days = var.selection_window_days
  }
}

resource "aws_backup_restore_testing_selection" "this" {
  name                      = var.restore_testing_selection_name
  restore_testing_plan_name = aws_backup_restore_testing_plan.this.name
  protected_resource_type   = "EBS"
  iam_role_arn              = var.restore_testing_role_arn

  # EBS selections require either protected_resource_arns or a condition set.
  # Select by tag so newly created, correctly tagged volumes are covered
  # automatically without maintaining an ARN list.
  protected_resource_conditions {
    string_equals {
      key   = "aws:ResourceTag/${var.restore_testing_tag_key}"
      value = var.restore_testing_tag_value
    }
  }
}
