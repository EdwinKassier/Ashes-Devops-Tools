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
    backup_role_arn          = null
    restore_testing_role_arn = null
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
}

run "explicit_backup_role_creates_no_stack_set" {
  command = plan

  assert {
    condition     = length(aws_cloudformation_stack_set.backup_role) == 0 && output.backup_role_arn == "arn:aws:iam::111111111111:role/aws-backup-role"
    error_message = "An explicit backup_role_arn must be used as-is with no StackSet."
  }
}
