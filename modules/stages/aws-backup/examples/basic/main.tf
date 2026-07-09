# Basic working example for the aws-backup stage.
#
# The stage spans two accounts, so it declares two providers: the default
# provider authenticates into the MANAGEMENT account (which owns the org
# BACKUP_POLICY) and aws.backup targets the delegated BACKUP account (which owns
# the Vault-Locked vault). In a real deployment each provider assumes a role in
# its target account; here they use the same credentials for a validate-only
# check. Run `terraform init && terraform validate` here.

provider "aws" {
  region = "eu-west-2"
  # Default provider = management account (owns the org BACKUP_POLICY).
  # assume_role { role_arn = "arn:aws:iam::111111111111:role/tfc-run-role" }
}

provider "aws" {
  alias  = "backup"
  region = "eu-west-2"
  # assume_role { role_arn = "arn:aws:iam::444444444444:role/tfc-run-role" }
}

module "aws_backup" {
  source = "../../"

  providers = {
    aws        = aws
    aws.backup = aws.backup
  }

  vault_name               = "org-backup-vault"
  kms_key_arn              = "arn:aws:kms:eu-west-2:444444444444:key/backup-cmk-0000"
  restore_testing_role_arn = "arn:aws:iam::444444444444:role/backup-restore-test"
  backup_role_arn          = "arn:aws:iam::111111111111:role/aws-backup-role"
  workloads_ou_id          = "ou-abcd-11111111"
  aws_region               = "eu-west-2"
}
