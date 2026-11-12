# Organization BACKUP_POLICY for the SRA landing zone.
#
# Defines an org-wide AWS Backup plan (a daily rule that writes to a vault of
# backup_vault_name in each member account) and attaches it to the Workloads OU,
# so every account beneath it inherits a baseline backup plan without
# per-account configuration. The management account owns this policy.
#
# The policy content uses AWS Organizations @@assign syntax and is built with
# jsonencode(). copy_actions (empty by default) copies each daily recovery
# point to other vaults: the locked central copy vault in the backup account,
# or a vault in a DR region. Destination ARNs may use the Organizations policy
# variable $account. Callers can override the whole document with a non-empty
# `content`.

locals {
  daily_rule = merge(
    {
      schedule_expression      = { "@@assign" = "cron(0 5 ? * * *)" }
      target_backup_vault_name = { "@@assign" = var.backup_vault_name }
      lifecycle                = { delete_after_days = { "@@assign" = tostring(var.retention_days) } }
    },
    length(var.copy_actions) == 0 ? {} : {
      copy_actions = {
        for c in var.copy_actions : c.destination_vault_arn => {
          target_backup_vault_arn = { "@@assign" = c.destination_vault_arn }
          lifecycle               = { delete_after_days = { "@@assign" = tostring(c.delete_after_days) } }
        }
      }
    },
  )

  policy_document = jsonencode({
    plans = {
      default = {
        regions = { "@@assign" = [var.default_region] }
        rules   = { daily = local.daily_rule }
        selections = {
          tags = {
            backup = {
              iam_role_arn = { "@@assign" = var.backup_role_arn }
              tag_key      = { "@@assign" = "backup" }
              tag_value    = { "@@assign" = ["true"] }
            }
          }
        }
      }
    }
  })
}

resource "aws_organizations_policy" "backup" {
  name    = var.policy_name
  type    = "BACKUP_POLICY"
  content = var.content != "" ? var.content : local.policy_document

  tags = var.tags
}

resource "aws_organizations_policy_attachment" "target" {
  policy_id = aws_organizations_policy.backup.id
  target_id = var.target_ou_id
}
