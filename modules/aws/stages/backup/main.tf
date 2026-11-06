# aws-backup stage (phase-2)
#
# Thin orchestration wrapper composing the organization backup baseline across
# two accounts:
#   - the DEFAULT provider authenticates into the MANAGEMENT account, which owns
#     the organization BACKUP_POLICY (an Organizations policy attached to the
#     Workloads OU).
#   - aws.backup targets the delegated BACKUP account, which owns the
#     KMS-encrypted, Compliance-mode Vault Lock (WORM) backup vault and the
#     restore testing plan.
#
# The vault is the WORM target for the org backup plan; the org policy points
# every account under the Workloads OU at the vault by name. The two children
# are joined by the vault name (backup_vault_name), which is the cross-account
# naming contract between the backup account's vault and the management
# account's policy.

# ---------------------------------------------------------------------------
# Backup vault + Vault Lock + restore testing (BACKUP account)
# ---------------------------------------------------------------------------

module "backup_vault" {
  source = "../../backup/backup-vault"
  providers = {
    aws = aws.backup
  }

  vault_name               = var.vault_name
  kms_key_arn              = var.kms_key_arn
  min_retention_days       = var.min_retention_days
  max_retention_days       = var.max_retention_days
  changeable_for_days      = var.changeable_for_days
  restore_testing_role_arn = var.restore_testing_role_arn
}

# ---------------------------------------------------------------------------
# Member-account AWS Backup service role (MANAGEMENT account StackSet)
#
# The org BACKUP_POLICY runs its jobs IN EACH member account, so the role it
# names must exist in every account under the Workloads OU. A service-managed
# StackSet (auto-deployment on) creates it there and in every account that joins
# the OU later; the policy then names it with the $account policy variable.
# Requires CloudFormation StackSets trusted access (enabled by aws-organization).
# ---------------------------------------------------------------------------

locals {
  create_backup_role = var.backup_role_arn == null
  backup_role_arn    = local.create_backup_role ? "arn:aws:iam::$account:role/${var.backup_role_name}" : var.backup_role_arn

  backup_role_template = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "AWS Backup service role for the organization BACKUP_POLICY (managed by the aws-backup stage)."
    Resources = {
      BackupServiceRole = {
        Type = "AWS::IAM::Role"
        Properties = {
          RoleName = var.backup_role_name
          AssumeRolePolicyDocument = {
            Version = "2012-10-17"
            Statement = [{
              Effect    = "Allow"
              Principal = { Service = "backup.amazonaws.com" }
              Action    = "sts:AssumeRole"
            }]
          }
          ManagedPolicyArns = [
            { "Fn::Sub" = "arn:$${AWS::Partition}:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup" },
            { "Fn::Sub" = "arn:$${AWS::Partition}:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores" },
          ]
        }
      }
    }
  })
}

resource "aws_cloudformation_stack_set" "backup_role" {
  count = local.create_backup_role ? 1 : 0

  name             = "aws-backup-org-role"
  description      = "AWS Backup service role for the organization BACKUP_POLICY in every Workloads-OU account."
  permission_model = "SERVICE_MANAGED"
  call_as          = var.backup_role_stack_set_call_as
  capabilities     = ["CAPABILITY_NAMED_IAM"]
  template_body    = local.backup_role_template

  auto_deployment {
    enabled                          = true
    retain_stacks_on_account_removal = false
  }

  managed_execution {
    active = true
  }

  operation_preferences {
    failure_tolerance_count = 0
    max_concurrent_count    = 10
    region_concurrency_type = "SEQUENTIAL"
  }

  lifecycle {
    # AWS populates administration_role_arn on SERVICE_MANAGED stack sets,
    # which otherwise shows as perpetual drift.
    ignore_changes = [administration_role_arn]
  }
}

resource "aws_cloudformation_stack_set_instance" "backup_role" {
  count = local.create_backup_role ? 1 : 0

  stack_set_name            = aws_cloudformation_stack_set.backup_role[0].name
  call_as                   = var.backup_role_stack_set_call_as
  stack_set_instance_region = var.aws_region
  retain_stack              = false

  deployment_targets {
    organizational_unit_ids = [var.workloads_ou_id]
  }

  operation_preferences {
    failure_tolerance_count = 0
    max_concurrent_count    = 10
  }
}

# ---------------------------------------------------------------------------
# Organization BACKUP_POLICY (MANAGEMENT account = default provider)
# ---------------------------------------------------------------------------

module "backup_org_policy" {
  source = "../../backup/backup-org-policy"

  backup_vault_name = var.vault_name
  backup_role_arn   = local.backup_role_arn
  target_ou_id      = var.workloads_ou_id
  default_region    = var.aws_region

  # The member-account role must exist before the policy schedules jobs.
  depends_on = [module.backup_vault, aws_cloudformation_stack_set_instance.backup_role]
}
