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
# The org policy runs its jobs in each member account and writes to a vault of
# this name IN THAT ACCOUNT. The member vaults come from the member-account
# StackSet (aws-organization by default; the legacy one below when enabled).
# The backup account's vault of the same name is locked (WORM) but receives
# nothing: the backup account is not in the Workloads OU.
#
# Central copy (enable_central_copy, off by default; compliance.backup
# .copy_to_central_vault in the config file) makes the backup account the WORM
# store: a new CMK-encrypted, Compliance-locked copy vault (copy_vault_name)
# accepts copies from the organization, org-wide cross-account backup is
# enabled in the management account, and the policy writes to the
# <vault_name>-cmk member vault (aws-organization member_backup_vault_encryption
# = cmk) and copies every recovery point to the copy vault. dr_region adds a
# copy to the <vault_name>-cmk vault in that region of the same member account.
# Restore testing moves to the copy vault. copy_vault_notification_topic_arn
# publishes the copy vault's failed backup, copy and restore events (restore
# testing included) to an SNS topic in the backup account.

# ---------------------------------------------------------------------------
# Backup vault + Vault Lock + restore testing (BACKUP account)
# ---------------------------------------------------------------------------

# Boundary propagation (tfc-oidc-baseline): the backup-account tfc-apply role may
# only create roles that carry its own permissions boundary. Derived from the
# aws.backup provider; only needed when the restore-testing role is created.
data "aws_caller_identity" "backup" {
  count    = local.derive_backup_boundary ? 1 : 0
  provider = aws.backup
}

data "aws_partition" "backup" {
  count    = local.derive_backup_boundary ? 1 : 0
  provider = aws.backup
}

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
  # With central copy on, this vault receives nothing, so testing it proves
  # nothing: restore testing moves to the copy vault.
  create_restore_testing = !var.enable_central_copy
  # The restore-testing role is created in the backup account.
  permissions_boundary_arn = local.backup_boundary_arn
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
  derive_backup_boundary = var.tfc_apply_boundary_policy_name != null && var.restore_testing_role_arn == null

  # The CMK member vault is the copy source: cross-account copy needs a
  # customer managed key on the source vault. aws-organization creates
  # <vault_name>-cmk (home and DR region) when compliance.backup is set.
  use_cmk_member_vault = var.enable_central_copy || var.dr_region != null
  member_vault_name    = coalesce(var.member_vault_name, local.use_cmk_member_vault ? "${var.vault_name}-cmk" : var.vault_name)

  central_copy_vault_arn = "arn:${var.partition}:backup:${var.aws_region}:${coalesce(var.backup_account_id, "000000000000")}:backup-vault:${var.copy_vault_name}"
  copy_actions = concat(
    var.enable_central_copy ? [{ destination_vault_arn = local.central_copy_vault_arn, delete_after_days = var.copy_retention_days }] : [],
    var.dr_region != null ? [{ destination_vault_arn = "arn:${var.partition}:backup:${coalesce(var.dr_region, "-")}:$account:backup-vault:${var.vault_name}-cmk", delete_after_days = var.dr_copy_retention_days }] : [],
  )

  # Copy vault key administration mirrors the security-stage CMKs: the backup
  # account's tfc-apply role administers the key (no usage, no PutKeyPolicy);
  # the member break-glass role there alone holds kms:PutKeyPolicy.
  copy_vault_key_admin_arn = coalesce(var.copy_vault_key_admin_arn, "arn:${var.partition}:iam::${coalesce(var.backup_account_id, "000000000000")}:role/tfc-apply")
  copy_vault_key_policy_admin_arns = var.copy_vault_key_policy_admin_role_name == null ? [] : [
    "arn:${var.partition}:iam::${coalesce(var.backup_account_id, "000000000000")}:role/${var.copy_vault_key_policy_admin_role_name}"
  ]
  # AWS services that use the copy vault key on behalf of backup-account
  # principals: Backup for copy-in and the vault, the others for restores.
  copy_vault_key_via_services = [for svc in ["backup", "ec2", "rds", "s3", "dynamodb", "elasticfilesystem"] : "${svc}.${var.aws_region}.amazonaws.com"]
  # Real AWS always returns a 12-digit account and an aws* partition; under
  # mock_provider these data sources return random strings the provider's ARN
  # validator rejects, so a malformed identity yields no boundary rather than
  # failing every mocked plan downstream (tests override the data sources).
  boundary_partition = try(data.aws_partition.backup[0].partition, null)
  boundary_account   = try(data.aws_caller_identity.backup[0].account_id, null)
  backup_boundary_arn = (
    local.derive_backup_boundary && can(regex("^aws(-[a-z]+)*$", local.boundary_partition)) && can(regex("^[0-9]{12}$", local.boundary_account))
    ? "arn:${local.boundary_partition}:iam::${local.boundary_account}:policy/${var.tfc_apply_boundary_policy_name}"
    : null
  )

  # The member-account role is deployed by aws-organization by default
  # (create_backup_service_role there): the aws-backup management role must not
  # hold CloudFormation StackSet rights, which would be an org-wide
  # role-deployment primitive. create_backup_role_stack_set = true keeps the
  # legacy in-stage StackSet for estates that apply aws-backup as the phase-0 role.
  create_backup_role = var.backup_role_arn == null && var.create_backup_role_stack_set
  backup_role_arn    = var.backup_role_arn == null ? "arn:${var.partition}:iam::$account:role/${var.backup_role_name}" : var.backup_role_arn

  # The BACKUP_POLICY writes to a vault named vault_name in each member account,
  # so the legacy StackSet creates it there too (retained on stack deletion).
  backup_role_template = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "AWS Backup service role and vault for the organization BACKUP_POLICY (managed by the aws-backup stage)."
    Resources = {
      MemberBackupVault = {
        Type                = "AWS::Backup::BackupVault"
        DeletionPolicy      = "Retain"
        UpdateReplacePolicy = "Retain"
        Properties = {
          BackupVaultName = var.vault_name
        }
      }
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

  backup_vault_name = local.member_vault_name
  backup_role_arn   = local.backup_role_arn
  target_ou_id      = var.workloads_ou_id
  default_region    = var.aws_region
  retention_days    = var.retention_days
  copy_actions      = local.copy_actions

  # The member-account role must exist before the policy schedules jobs, and
  # the copy vault and cross-account backup before the policy copies to them.
  depends_on = [module.backup_vault, aws_cloudformation_stack_set_instance.backup_role, module.copy_vault, aws_backup_global_settings.this]
}

# ---------------------------------------------------------------------------
# Central copy (enable_central_copy, off by default)
# ---------------------------------------------------------------------------

# Organization-wide cross-account backup (management account). Without it,
# AWS Backup rejects copy jobs to another account in the organization.
resource "aws_backup_global_settings" "this" {
  count = var.enable_central_copy ? 1 : 0

  global_settings = {
    "isCrossAccountBackupEnabled" = "true"
  }
}

# The copy vault key (BACKUP account), unless copy_vault_kms_key_arn is given.
# Tagged protected = true: the deny-tamper SCP and the tfc-apply boundary let
# only break-glass disable it, schedule its deletion or rewrite its policy, so
# the locked copies cannot be crypto-shredded. Usage is granted to the backup
# account's principals through the listed AWS services only.
module "copy_vault_key" {
  source = "../../data/kms-key"
  count  = var.enable_central_copy && var.copy_vault_kms_key_arn == null ? 1 : 0
  providers = {
    aws = aws.backup
  }

  alias                  = "backup-copy-vault"
  org_id                 = coalesce(var.organization_id, "unset")
  management_account_id  = coalesce(var.management_account_id, "unset")
  key_admin_arn          = local.copy_vault_key_admin_arn
  key_policy_admin_arns  = local.copy_vault_key_policy_admin_arns
  key_account_id         = var.backup_account_id
  log_service_principals = []
  key_user_arns          = ["arn:${var.partition}:iam::${coalesce(var.backup_account_id, "000000000000")}:root"]
  via_services           = local.copy_vault_key_via_services
  enable_key_user_grants = true
  enable_protection_tag  = true
}

# The locked WORM destination for every member recovery point. A new vault,
# not the existing one: changing a vault's key forces replacement, and the
# existing vault may already be locked.
module "copy_vault" {
  source = "../../backup/backup-vault"
  count  = var.enable_central_copy ? 1 : 0
  providers = {
    aws = aws.backup
  }

  vault_name                      = var.copy_vault_name
  kms_key_arn                     = coalesce(var.copy_vault_kms_key_arn, try(module.copy_vault_key[0].key_arn, null))
  min_retention_days              = var.min_retention_days
  max_retention_days              = var.max_retention_days
  changeable_for_days             = var.changeable_for_days
  allow_copy_from_organization_id = var.organization_id
  restore_testing_plan_name       = "org_restore_test_copy"
  restore_testing_resource_types  = ["EBS", "EC2", "RDS", "Aurora", "S3", "DynamoDB", "EFS"]
  restore_testing_role_arn        = var.restore_testing_role_arn
  notification_topic_arn          = var.copy_vault_notification_topic_arn
  # A distinct name: the backup_vault role of the default name is destroyed in
  # the same apply, and IAM names must be unique.
  restore_testing_role_name = "aws-backup-restore-testing-copy"
  partition                 = var.partition
  permissions_boundary_arn  = local.backup_boundary_arn
}
