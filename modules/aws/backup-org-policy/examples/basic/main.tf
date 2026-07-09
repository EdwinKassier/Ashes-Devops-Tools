# Basic working example for the aws/backup-org-policy module.
# Run `terraform init && terraform validate` here to check it.

module "backup_org_policy" {
  source = "../../"

  backup_role_arn = "arn:aws:iam::123456789012:role/OrgBackupRole"
  target_ou_id    = "ou-abcd-1example"
}
