# Basic working example for the aws/cloudtrail-org module.
# Run `terraform init && terraform validate` here to check it.
#
# In a real deployment this module is instantiated with the management-account
# (or CloudTrail delegated-admin) provider, and log_archive_bucket / kms_key_arn
# reference the central Log-Archive bucket and its KMS key in the Log-Archive
# account.

module "cloudtrail_org" {
  source = "../../"

  log_archive_bucket = "sra-log-archive-bucket"
  kms_key_arn        = "arn:aws:kms:us-east-1:111111111111:key/00000000-0000-0000-0000-000000000000"
}
