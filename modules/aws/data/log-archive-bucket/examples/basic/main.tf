# Basic working example for the aws/log-archive-bucket module.
# Run `terraform init && terraform validate` here to check it.

module "log_archive_bucket" {
  source = "../../"

  log_archive_bucket_name = "example-org-log-archive"
  kms_key_arn             = "arn:aws:kms:eu-west-2:111111111111:key/00000000-0000-0000-0000-000000000000"
  org_id                  = "o-abc123xyz0"
}
