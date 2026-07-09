# Resource-assertion tests for the aws/backup-org-policy module.
#
# Asserts on configured attributes known at plan time under mock_provider:
# the policy type and the rendered @@assign JSON content.

mock_provider "aws" {}

run "backup_policy_rendered_and_attached" {
  command = plan

  variables {
    backup_role_arn   = "arn:aws:iam::123456789012:role/OrgBackupRole"
    target_ou_id      = "ou-abcd-1example"
    backup_vault_name = "org-backup-vault"
  }

  assert {
    condition     = aws_organizations_policy.backup.type == "BACKUP_POLICY"
    error_message = "Policy type must be BACKUP_POLICY"
  }

  assert {
    # Rendered content must be valid JSON with the expected @@assign structure.
    condition     = jsondecode(aws_organizations_policy.backup.content).plans.default.regions != null
    error_message = "Rendered policy must decode to Organizations @@assign JSON with plans.default.regions"
  }

  assert {
    # The templated vault name must appear in the rendered daily rule.
    condition     = jsondecode(aws_organizations_policy.backup.content).plans.default.rules.daily.target_backup_vault_name["@@assign"] == var.backup_vault_name
    error_message = "Rendered policy must target the configured backup vault name"
  }
}
