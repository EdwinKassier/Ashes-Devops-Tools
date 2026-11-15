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

run "module_tags_applied" {
  command = plan

  variables {
    backup_role_arn   = "arn:aws:iam::123456789012:role/OrgBackupRole"
    target_ou_id      = "ou-abcd-1example"
    backup_vault_name = "org-backup-vault"
    tags              = { Owner = "test" }
  }

  assert {
    condition     = aws_organizations_policy.backup.tags["Owner"] == "test"
    error_message = "module-level tags must land on aws_organizations_policy.backup"
  }
}

# copy_actions: each copy renders under rules.daily.copy_actions, keyed by its
# destination vault ARN, with its own lifecycle. retention_days drives the
# daily rule lifecycle.
run "copy_actions_rendered" {
  command = plan

  variables {
    backup_role_arn   = "arn:aws:iam::123456789012:role/OrgBackupRole"
    target_ou_id      = "ou-abcd-1example"
    backup_vault_name = "org-backup-vault-cmk"
    retention_days    = 400
    copy_actions = [
      { destination_vault_arn = "arn:aws:backup:eu-west-2:444444444444:backup-vault:org-backup-copy-vault", delete_after_days = 400 },
      { destination_vault_arn = "arn:aws:backup:eu-west-1:$account:backup-vault:org-backup-vault-cmk", delete_after_days = 35 },
    ]
  }

  assert {
    condition = (
      jsondecode(aws_organizations_policy.backup.content).plans.default.rules.daily.copy_actions["arn:aws:backup:eu-west-2:444444444444:backup-vault:org-backup-copy-vault"].target_backup_vault_arn["@@assign"] == "arn:aws:backup:eu-west-2:444444444444:backup-vault:org-backup-copy-vault" &&
      jsondecode(aws_organizations_policy.backup.content).plans.default.rules.daily.copy_actions["arn:aws:backup:eu-west-1:$account:backup-vault:org-backup-vault-cmk"].lifecycle.delete_after_days["@@assign"] == "35"
    )
    error_message = "each copy action must render under rules.daily.copy_actions keyed by its destination vault ARN."
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.backup.content).plans.default.rules.daily.lifecycle.delete_after_days["@@assign"] == "400"
    error_message = "retention_days must drive the daily rule lifecycle (it was hard-coded to 365)."
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.backup.content).plans.default.rules.daily.target_backup_vault_name["@@assign"] == "org-backup-vault-cmk"
    error_message = "the daily rule must write to backup_vault_name."
  }
}

run "no_copy_actions_by_default" {
  command = plan

  variables {
    backup_role_arn = "arn:aws:iam::123456789012:role/OrgBackupRole"
    target_ou_id    = "ou-abcd-1example"
  }

  assert {
    condition     = !can(jsondecode(aws_organizations_policy.backup.content).plans.default.rules.daily.copy_actions)
    error_message = "the default policy must not carry copy_actions (unchanged behaviour)."
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.backup.content).plans.default.rules.daily.lifecycle.delete_after_days["@@assign"] == "365"
    error_message = "the default retention must stay 365 days."
  }

  # The default document is the one the deleted policies/backup-policy.json
  # rendered, so an existing estate plans no content change.
  assert {
    condition = jsondecode(aws_organizations_policy.backup.content) == {
      plans = {
        default = {
          regions = { "@@assign" = ["eu-west-2"] }
          rules = {
            daily = {
              schedule_expression      = { "@@assign" = "cron(0 5 ? * * *)" }
              target_backup_vault_name = { "@@assign" = "org-backup-vault" }
              lifecycle                = { delete_after_days = { "@@assign" = "365" } }
            }
          }
          selections = {
            tags = {
              backup = {
                iam_role_arn = { "@@assign" = "arn:aws:iam::123456789012:role/OrgBackupRole" }
                tag_key      = { "@@assign" = "backup" }
                tag_value    = { "@@assign" = ["true"] }
              }
            }
          }
        }
      }
    }
    error_message = "the default policy document must equal the former templated document."
  }
}
