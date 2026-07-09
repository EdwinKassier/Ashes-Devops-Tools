# Organization BACKUP_POLICY for the SRA landing zone.
#
# Defines an org-wide AWS Backup plan (a daily rule targeting a central vault)
# and attaches it to the Workloads OU so every account beneath it inherits a
# baseline backup plan without per-account configuration. The management /
# backup-admin account owns this policy.
#
# The policy content uses AWS Organizations @@assign syntax. It is rendered from
# a templated JSON file; callers can override the whole document by passing a
# non-empty `content`. Any literal AWS-policy built-ins (e.g. $account) in the
# template are escaped as $${...} so templatefile renders them verbatim.

resource "aws_organizations_policy" "backup" {
  name = var.policy_name
  type = "BACKUP_POLICY"
  content = var.content != "" ? var.content : templatefile("${path.module}/policies/backup-policy.json", {
    default_region    = var.default_region
    backup_vault_name = var.backup_vault_name
    backup_role_arn   = var.backup_role_arn
  })
}

resource "aws_organizations_policy_attachment" "target" {
  policy_id = aws_organizations_policy.backup.id
  target_id = var.target_ou_id
}
