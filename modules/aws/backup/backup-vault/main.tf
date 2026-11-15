# KMS-encrypted AWS Backup vault with Compliance-mode Vault Lock and restore
# testing for the SRA landing zone. Runs in the delegated Backup account.
#
# Vault Lock is configured in Compliance mode (changeable_for_days is
# non-null): once the cooling-off window elapses the lock is immutable and
# recovery points cannot be deleted before min_retention_days by anyone,
# including the root user. This is the control that makes backups
# tamper-proof against ransomware / rogue admins.
#
# allow_copy_from_organization_id adds a vault access policy that accepts
# backup:CopyIntoBackupVault from principals in that organization only, so the
# vault can be the destination of the org BACKUP_POLICY copy actions (the
# aws-backup stage's copy vault). Without it the vault receives no copies.
#
# Restore testing (aws_backup_restore_testing_plan + _selection, on unless
# create_restore_testing = false) periodically restores recovery points from
# this vault only. One selection per restore_testing_resource_types entry: EBS
# selects by a tag condition; every other type selects all protected resources
# of that type ("*"). Restore testing proves recoverability only when the vault
# receives recovery points.
#
# notification_topic_arn (off by default) publishes failed backup, copy and
# restore events (restore-testing restores included) and RECOVERY_POINT_MODIFIED
# to an SNS topic.

locals {
  create_restore_testing_role = var.create_restore_testing && var.restore_testing_role_arn == null
  restore_testing_role_arn = !var.create_restore_testing ? null : (
    local.create_restore_testing_role ? aws_iam_role.restore_testing[0].arn : var.restore_testing_role_arn
  )
}

# Restore-testing service role (created unless an existing ARN is passed):
# trusted by backup.amazonaws.com only, with the AWS managed restore policy.
resource "aws_iam_role" "restore_testing" {
  count = local.create_restore_testing_role ? 1 : 0
  name  = var.restore_testing_role_name

  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "restore_testing" {
  count      = local.create_restore_testing_role ? 1 : 0
  role       = aws_iam_role.restore_testing[0].name
  policy_arn = "arn:${var.partition}:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

resource "aws_backup_vault" "this" {
  # checkov:skip=CKV_AWS_166:The key is caller-supplied (kms_key_arn). The aws-backup copy vault gets a customer managed key from a sibling module output, which Checkov cannot resolve; plan_assertions (copy_in_policy_and_restore_types) proves the key is used. An empty kms_key_arn uses the AWS managed key by design.
  name        = var.vault_name
  kms_key_arn = var.kms_key_arn != "" ? var.kms_key_arn : null
  tags        = var.tags
}

resource "aws_backup_vault_lock_configuration" "this" {
  backup_vault_name = aws_backup_vault.this.name

  # A non-null changeable_for_days puts the lock in Compliance mode (WORM):
  # the configuration can only be changed/deleted during this cooling-off window.
  changeable_for_days = var.changeable_for_days
  min_retention_days  = var.min_retention_days
  max_retention_days  = var.max_retention_days
}

resource "aws_backup_vault_policy" "copy_in" {
  count             = var.allow_copy_from_organization_id != null ? 1 : 0
  backup_vault_name = aws_backup_vault.this.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowOrganizationCopyIn"
      Effect    = "Allow"
      Principal = { AWS = "*" }
      Action    = "backup:CopyIntoBackupVault"
      Resource  = "*"
      Condition = { StringEquals = { "aws:PrincipalOrgID" = var.allow_copy_from_organization_id } }
    }]
  })
}

# Failed jobs and changed recovery points publish to the caller's SNS topic.
# Restore-testing restores run as restore jobs, so their failures are expected
# as RESTORE_JOB_FAILED (not yet proven against a real apply: known-gaps).
resource "aws_backup_vault_notifications" "this" {
  count             = var.notification_topic_arn != null ? 1 : 0
  backup_vault_name = aws_backup_vault.this.name
  sns_topic_arn     = var.notification_topic_arn
  backup_vault_events = [
    "BACKUP_JOB_FAILED", "COPY_JOB_FAILED", "RESTORE_JOB_FAILED",
    "S3_BACKUP_OBJECT_FAILED", "S3_RESTORE_OBJECT_FAILED", "RECOVERY_POINT_MODIFIED",
  ]
}

resource "aws_backup_restore_testing_plan" "this" {
  count = var.create_restore_testing ? 1 : 0

  name                = var.restore_testing_plan_name
  schedule_expression = var.restore_testing_schedule
  start_window_hours  = var.start_window_hours

  recovery_point_selection {
    algorithm             = "LATEST_WITHIN_WINDOW"
    include_vaults        = [aws_backup_vault.this.arn]
    recovery_point_types  = ["SNAPSHOT"]
    selection_window_days = var.selection_window_days
  }

  tags = var.tags
}

resource "aws_backup_restore_testing_selection" "this" {
  for_each = var.create_restore_testing ? toset(var.restore_testing_resource_types) : toset([])

  # EBS keeps the original selection name, so an existing selection moves in
  # state (moved block below) instead of being replaced.
  name                      = each.key == "EBS" ? var.restore_testing_selection_name : "${var.restore_testing_selection_name}_${lower(each.key)}"
  restore_testing_plan_name = aws_backup_restore_testing_plan.this[0].name
  protected_resource_type   = each.key
  iam_role_arn              = local.restore_testing_role_arn

  # EBS selects by tag, so newly created, correctly tagged volumes are covered
  # without an ARN list. Every other type selects all protected resources of
  # that type in the vault ("*").
  protected_resource_arns = each.key == "EBS" ? null : ["*"]

  dynamic "protected_resource_conditions" {
    for_each = each.key == "EBS" ? [1] : []
    content {
      string_equals {
        key   = "aws:ResourceTag/${var.restore_testing_tag_key}"
        value = var.restore_testing_tag_value
      }
    }
  }

  depends_on = [aws_iam_role_policy_attachment.restore_testing]
}

moved {
  from = aws_backup_restore_testing_selection.this
  to   = aws_backup_restore_testing_selection.this["EBS"]
}

moved {
  from = aws_backup_restore_testing_plan.this
  to   = aws_backup_restore_testing_plan.this[0]
}
