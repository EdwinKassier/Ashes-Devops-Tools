# Basic working example for the aws/backup-vault module.
# Run `terraform init && terraform validate` here to check it.

module "backup_vault" {
  source = "../../"

  kms_key_arn              = "arn:aws:kms:eu-west-2:123456789012:key/00000000-0000-0000-0000-000000000000"
  restore_testing_role_arn = "arn:aws:iam::123456789012:role/BackupRestoreTestRole"
}
