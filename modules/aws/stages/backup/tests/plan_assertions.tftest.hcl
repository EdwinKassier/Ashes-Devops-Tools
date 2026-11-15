# Plan-assertion tests for the aws-backup stage.
#
# Uses two mock providers (default = management + aws.backup) so no AWS
# credentials are required. The composition joins the two children by the vault
# name (the cross-account naming contract): the vault is created in the backup
# account, and the management-account org BACKUP_POLICY targets it by name.
#
# The vault child's mock-generated ARN and the org policy's id are unknown at
# plan, so both children are overridden with known outputs and the run is driven
# with `command = apply`. That makes the stage's output-wiring (input <- child
# output edges) concrete: the vault ARN and the org policy id surface through the
# stage outputs. The org policy's BACKUP_POLICY type and the rendered vault-name
# @@assign content are proven in the child module's own tests
# (modules/aws/backup-org-policy/tests) — nested-module resources are not
# addressable from this parent test, so the wiring is what is asserted here.

mock_provider "aws" {}
mock_provider "aws" { alias = "backup" }

variables {
  vault_name               = "org-backup-vault"
  restore_testing_role_arn = "arn:aws:iam::444444444444:role/backup-restore-test"
  backup_role_arn          = "arn:aws:iam::111111111111:role/aws-backup-role"
  workloads_ou_id          = "ou-abcd-11111111"
}

# Feed known outputs for both children so the stage output-wiring assertions are
# non-vacuous under mock (the raw mock attributes are unknown at plan).
override_module {
  target  = module.backup_vault
  outputs = { vault_arn = "arn:aws:backup:eu-west-2:444444444444:backup-vault:org-backup-vault" }
}

override_module {
  target  = module.backup_org_policy
  outputs = { policy_id = "p-backup00000000" }
}

override_module {
  target  = module.copy_vault
  outputs = { vault_arn = "arn:aws:backup:eu-west-2:444444444444:backup-vault:org-backup-copy-vault" }
}

run "composes_backup_baseline" {
  command = apply

  # The Vault-Locked vault ARN surfaces through the stage output (wiring proof):
  # it must be the ARN produced by the vault child in the backup account.
  assert {
    condition     = output.vault_arn == "arn:aws:backup:eu-west-2:444444444444:backup-vault:org-backup-vault"
    error_message = "vault_arn output must surface module.backup_vault.vault_arn"
  }

  # The org BACKUP_POLICY id surfaces through the stage output (wiring proof):
  # it must be the id produced by the org-policy child in the management account.
  assert {
    condition     = output.backup_policy_id == "p-backup00000000"
    error_message = "backup_policy_id output must surface module.backup_org_policy.policy_id"
  }
}

# Default roles: backup_role_arn = null deploys the member-account backup role
# through a service-managed StackSet on the Workloads OU and renders a
# $account-templated ARN into the org policy; restore_testing_role_arn = null is
# created by the vault child (asserted in modules/aws/backup/backup-vault).
run "backup_role_stack_set_by_default" {
  command = plan

  variables {
    backup_role_arn              = null
    create_backup_role_stack_set = true
    restore_testing_role_arn     = null
  }

  assert {
    condition     = output.backup_role_arn == "arn:aws:iam::$account:role/aws-backup-org-role"
    error_message = "The org policy must name the StackSet role via the $account policy variable."
  }

  assert {
    condition     = aws_cloudformation_stack_set.backup_role[0].permission_model == "SERVICE_MANAGED" && aws_cloudformation_stack_set.backup_role[0].auto_deployment[0].enabled
    error_message = "The backup role must be deployed by an auto-deploying service-managed StackSet."
  }

  assert {
    condition     = tolist(aws_cloudformation_stack_set_instance.backup_role[0].deployment_targets[0].organizational_unit_ids) == tolist(["ou-abcd-11111111"])
    error_message = "The StackSet must target the Workloads OU the policy is attached to."
  }

  assert {
    condition     = jsondecode(aws_cloudformation_stack_set.backup_role[0].template_body).Resources.BackupServiceRole.Properties.AssumeRolePolicyDocument.Statement[0].Principal.Service == "backup.amazonaws.com"
    error_message = "The StackSet role must be trusted by backup.amazonaws.com only."
  }

  assert {
    condition     = jsondecode(aws_cloudformation_stack_set.backup_role[0].template_body).Resources.MemberBackupVault.Properties.BackupVaultName == var.vault_name
    error_message = "The legacy StackSet must create the member-account vault the BACKUP_POLICY targets."
  }
}

run "explicit_backup_role_creates_no_stack_set" {
  command = plan

  assert {
    condition     = length(aws_cloudformation_stack_set.backup_role) == 0 && output.backup_role_arn == "arn:aws:iam::111111111111:role/aws-backup-role"
    error_message = "An explicit backup_role_arn must be used as-is with no StackSet."
  }
}

# Boundary propagation (tfc-oidc-baseline): when the stage creates the
# restore-testing role in the backup account it derives that account's
# tfc-apply-boundary from the aws.backup provider; an existing role ARN skips it.
run "restore_testing_role_carries_tfc_apply_boundary" {
  command = plan

  variables {
    restore_testing_role_arn = null
  }

  override_data {
    target = data.aws_caller_identity.backup[0]
    values = { account_id = "444444444444" }
  }

  override_data {
    target = data.aws_partition.backup[0]
    values = { partition = "aws" }
  }

  assert {
    condition     = local.backup_boundary_arn == "arn:aws:iam::444444444444:policy/tfc-apply-boundary"
    error_message = "The backup boundary ARN (passed to backup_vault) must be derived from the aws.backup provider."
  }
}

run "existing_restore_role_needs_no_boundary" {
  command = plan

  assert {
    condition     = local.backup_boundary_arn == null && length(data.aws_caller_identity.backup) == 0
    error_message = "With an existing restore_testing_role_arn no boundary lookup is needed."
  }
}

# Default: aws-organization owns the member role; aws-backup only references it.
run "backup_role_referenced_not_deployed_by_default" {
  command = plan

  variables {
    backup_role_arn = null
  }

  assert {
    condition     = length(aws_cloudformation_stack_set.backup_role) == 0 && output.backup_role_arn == "arn:aws:iam::$account:role/aws-backup-org-role"
    error_message = "by default the stage must reference the aws-organization-deployed role and create no StackSet."
  }
}

# compliance.backup.copy_to_central_vault: the BACKUP_POLICY writes to the CMK
# member vault and copies every recovery point to the locked copy vault in the
# backup account and to the member DR vault; cross-account backup is enabled in
# the management account.
run "central_copy_wiring" {
  command = apply

  variables {
    enable_central_copy    = true
    organization_id        = "o-abc1234567"
    backup_account_id      = "444444444444"
    copy_vault_kms_key_arn = "arn:aws:kms:eu-west-2:444444444444:key/11111111-2222-3333-4444-555555555555"
    dr_region              = "eu-west-1"
  }

  assert {
    condition = output.copy_destination_vault_arns == [
      "arn:aws:backup:eu-west-2:444444444444:backup-vault:org-backup-copy-vault",
      "arn:aws:backup:eu-west-1:$account:backup-vault:org-backup-vault-cmk",
    ]
    error_message = "the stage must copy every recovery point to the locked central copy vault and to the member DR vault."
  }

  assert {
    condition     = output.policy_target_vault_name == "org-backup-vault-cmk"
    error_message = "with central copy on, the BACKUP_POLICY must write to the CMK member vault."
  }

  assert {
    condition     = jsondecode(aws_backup_global_settings.this[0].global_settings["isCrossAccountBackupEnabled"]) == true
    error_message = "cross-account backup must be enabled in the management account."
  }

  assert {
    condition     = output.copy_vault_arn == "arn:aws:backup:eu-west-2:444444444444:backup-vault:org-backup-copy-vault" && length(module.copy_vault_key) == 0
    error_message = "an explicit copy_vault_kms_key_arn must be used and no key created."
  }
}

run "central_copy_off_by_default" {
  command = apply

  assert {
    condition     = output.copy_destination_vault_arns == [] && length(aws_backup_global_settings.this) == 0
    error_message = "the default stage must not copy or touch global settings."
  }

  assert {
    condition     = output.policy_target_vault_name == "org-backup-vault" && output.copy_vault_arn == null && length(module.copy_vault) == 0 && length(module.copy_vault_key) == 0
    error_message = "the default stage must keep writing to vault_name and create no copy vault or key."
  }
}

# Without an explicit key the stage creates a protected CMK in the backup
# account for the copy vault.
run "central_copy_creates_copy_vault_key" {
  command = plan

  variables {
    enable_central_copy   = true
    organization_id       = "o-abc1234567"
    backup_account_id     = "444444444444"
    management_account_id = "111111111111"
  }

  assert {
    condition     = length(module.copy_vault_key) == 1 && length(module.copy_vault) == 1
    error_message = "enable_central_copy without copy_vault_kms_key_arn must create the copy vault key and the copy vault."
  }

  assert {
    condition     = output.copy_destination_vault_arns == ["arn:aws:backup:eu-west-2:444444444444:backup-vault:org-backup-copy-vault"]
    error_message = "without dr_region only the central copy vault is a copy destination."
  }
}

# compliance.backup.dr_region alone: aws-organization creates the CMK member
# vaults (home and DR region), so the policy writes to the CMK vault and
# copies to the DR region, with no cross-account copy.
run "dr_copy_without_central_copy" {
  command = apply

  variables {
    dr_region = "eu-west-1"
  }

  assert {
    condition     = output.copy_destination_vault_arns == ["arn:aws:backup:eu-west-1:$account:backup-vault:org-backup-vault-cmk"] && output.policy_target_vault_name == "org-backup-vault-cmk"
    error_message = "dr_region alone must copy to the member DR vault from the CMK member vault."
  }

  assert {
    condition     = length(aws_backup_global_settings.this) == 0 && length(module.copy_vault) == 0
    error_message = "dr_region alone must not enable cross-account backup or create the copy vault."
  }
}
