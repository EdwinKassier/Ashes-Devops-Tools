# Basic working example for the aws-organization stage.
# Uses the default foundational account set and the SRA OU/policy defaults;
# supplies only the required account-qualified carve-out ARNs and log-archive
# bucket name. Run `terraform init && terraform validate` here to check it.

module "aws_organization" {
  source = "../../"

  terraform_run_role_arn  = "arn:aws:iam::111111111111:role/tfc-run-role"
  break_glass_role_arn    = "arn:aws:iam::111111111111:role/break-glass"
  log_archive_bucket_name = "sra-log-archive-111111111111"
}
