# Basic working example for the aws/systems-manager module.
# Wires the Session Manager document to an S3 log bucket and KMS key, and takes
# the patch/inventory defaults. Run `terraform init && terraform validate` here.

module "systems_manager" {
  source = "../../"

  log_bucket_name = "org-ssm-session-logs"
  kms_key_id      = "arn:aws:kms:us-east-1:111111111111:key/EXAMPLE-KEY-ID"
}
