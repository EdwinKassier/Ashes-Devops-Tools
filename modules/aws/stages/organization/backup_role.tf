# Member-account AWS Backup service role (Workloads OU), deployed from the
# management account by a service-managed StackSet. It lives here, with the
# other org-wide role StackSets, so the least-privilege aws-backup management
# role needs no CloudFormation rights (a StackSet is an org-wide
# role-deployment primitive). aws-backup's BACKUP_POLICY names it with
# arn:aws:iam::$account:role/<backup_service_role_name>.
#
# The same StackSet creates the member-account backup vault. A BACKUP_POLICY
# runs its jobs in each member account and writes to a vault of the given name
# IN THAT ACCOUNT, so every account under the policy needs one (AWS Backup
# policy syntax docs). The vault is retained if the stack is deleted, because a
# vault that holds recovery points cannot be deleted. It uses the AWS managed
# aws/backup key.
#
# Cross-account copy needs a customer managed key on the source vault, and a
# vault's key cannot change after creation. member_backup_vault_encryption =
# "cmk" therefore ADDS a key and a second vault (<name>-cmk) next to the
# original one, which keeps its recovery points. The key is tagged
# protected = true, so the deny-tamper SCP lets only break-glass change its
# policy, disable it or schedule its deletion. Its policy lets the backup
# account (BackupAccountId parameter) use it for copy jobs. An optional second
# StackSet creates the same key and vault in member_backup_dr_region.

locals {
  member_backup_cmk = var.member_backup_vault_encryption == "cmk"

  # A conditional, not try(): an explicit value must stay known at plan, and the
  # variable validation already requires the backup account in cmk mode.
  backup_copy_account_id = var.backup_copy_account_id != null ? var.backup_copy_account_id : (
    contains(keys(local.all_accounts), "backup") ? module.account["backup"].account_id : null
  )

  member_backup_key_resource = {
    MemberBackupVaultKey = {
      Type                = "AWS::KMS::Key"
      DeletionPolicy      = "Retain"
      UpdateReplacePolicy = "Retain"
      Properties = {
        Description       = "AWS Backup member vault key: cross-account copy to the backup account (managed by aws-organization)."
        EnableKeyRotation = true
        KeyPolicy = {
          Version = "2012-10-17"
          Statement = [
            {
              Sid       = "AccountAdministration"
              Effect    = "Allow"
              Principal = { AWS = { "Fn::Sub" = "arn:$${AWS::Partition}:iam::$${AWS::AccountId}:root" } }
              Action    = "kms:*"
              Resource  = "*"
            },
            {
              Sid       = "BackupAccountCopy"
              Effect    = "Allow"
              Principal = { AWS = { "Fn::Sub" = "arn:$${AWS::Partition}:iam::$${BackupAccountId}:root" } }
              Action    = ["kms:Decrypt", "kms:DescribeKey", "kms:CreateGrant", "kms:ReEncrypt*", "kms:GenerateDataKey*"]
              Resource  = "*"
            },
          ]
        }
        Tags = [{ Key = "protected", Value = "true" }]
      }
    }
  }

  member_backup_vault_cmk_resource = {
    MemberBackupVaultCmk = {
      Type                = "AWS::Backup::BackupVault"
      DeletionPolicy      = "Retain"
      UpdateReplacePolicy = "Retain"
      Properties = {
        BackupVaultName  = "${var.member_backup_vault_name}-cmk"
        EncryptionKeyArn = { "Fn::GetAtt" = ["MemberBackupVaultKey", "Arn"] }
      }
    }
  }

  # Indexed tuples (not conditionals): the alternatives have different keys.
  member_backup_vault_resource = [{}, merge(
    {
      MemberBackupVault = {
        Type                = "AWS::Backup::BackupVault"
        DeletionPolicy      = "Retain"
        UpdateReplacePolicy = "Retain"
        Properties = {
          BackupVaultName = var.member_backup_vault_name
        }
      }
    },
    [{}, merge(local.member_backup_key_resource, local.member_backup_vault_cmk_resource)][local.member_backup_cmk ? 1 : 0],
  )][var.create_member_backup_vault ? 1 : 0]

  backup_parameters = {
    BackupAccountId = { Type = "String", AllowedPattern = "^[0-9]{12}$" }
  }

  # The default (aws_managed) template has no Parameters section, so it stays
  # byte-identical to the template from before the cmk mode existed.
  backup_service_role_template = jsonencode(merge([{}, { Parameters = local.backup_parameters }][local.member_backup_cmk ? 1 : 0], {
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "AWS Backup service role and vault for the organization BACKUP_POLICY (managed by aws-organization)."
    Resources = merge(local.member_backup_vault_resource, {
      BackupServiceRole = {
        Type = "AWS::IAM::Role"
        Properties = {
          RoleName = var.backup_service_role_name
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
    })
  }))
}

resource "aws_cloudformation_stack_set" "backup_service_role" {
  count = var.create_backup_service_role ? 1 : 0

  name             = var.backup_service_role_stack_set_name
  description      = "AWS Backup service role for the organization BACKUP_POLICY in every Workloads-OU account."
  permission_model = "SERVICE_MANAGED"
  capabilities     = ["CAPABILITY_NAMED_IAM"]
  template_body    = local.backup_service_role_template
  parameters       = local.member_backup_cmk ? { BackupAccountId = local.backup_copy_account_id } : null

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
    ignore_changes = [administration_role_arn]
  }
}

resource "aws_cloudformation_stack_set_instance" "backup_service_role" {
  count = var.create_backup_service_role ? 1 : 0

  stack_set_name            = aws_cloudformation_stack_set.backup_service_role[0].name
  stack_set_instance_region = var.backup_service_role_region
  retain_stack              = false

  deployment_targets {
    organizational_unit_ids = [module.organization.ou_ids["Workloads"]]
  }

  operation_preferences {
    failure_tolerance_count = 0
    max_concurrent_count    = 10
  }
}

# DR-region key and vault (member_backup_dr_region): the cross-region copy
# target. A separate StackSet because the role StackSet deploys to one region.
# IAM roles are global, so this template holds only the key and the vault.
resource "aws_cloudformation_stack_set" "member_backup_dr_vault" {
  count = var.create_backup_service_role && var.create_member_backup_vault && local.member_backup_cmk && var.member_backup_dr_region != null ? 1 : 0

  name             = "${var.backup_service_role_stack_set_name}-dr-vault"
  description      = "AWS Backup DR-region key and vault in every Workloads-OU account (cross-region copy target)."
  permission_model = "SERVICE_MANAGED"
  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "AWS Backup DR-region key and vault (managed by aws-organization)."
    Parameters               = local.backup_parameters
    Resources                = merge(local.member_backup_key_resource, local.member_backup_vault_cmk_resource)
  })
  parameters = { BackupAccountId = local.backup_copy_account_id }

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
    ignore_changes = [administration_role_arn]
  }
}

resource "aws_cloudformation_stack_set_instance" "member_backup_dr_vault" {
  count = length(aws_cloudformation_stack_set.member_backup_dr_vault)

  stack_set_name            = aws_cloudformation_stack_set.member_backup_dr_vault[0].name
  stack_set_instance_region = var.member_backup_dr_region
  retain_stack              = false

  deployment_targets {
    organizational_unit_ids = [module.organization.ou_ids["Workloads"]]
  }

  operation_preferences {
    failure_tolerance_count = 0
    max_concurrent_count    = 10
  }
}
