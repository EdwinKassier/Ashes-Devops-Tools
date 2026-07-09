# Basic working example for the aws/log-archive-bucket module.
# Run `terraform init && terraform validate` here to check it.

module "log_archive_bucket" {
  source = "../../"

  log_archive_bucket_name = "acme-org-log-archive"
  kms_key_arn             = "arn:aws:kms:eu-west-1:111122223333:key/abcd-1234"
  org_id                  = "o-abc123xyz0"
}
