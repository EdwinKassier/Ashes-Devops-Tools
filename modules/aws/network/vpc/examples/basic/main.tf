# Basic working example for the aws/vpc module.
# Uses the module defaults (10.0.0.0/16, 2 AZs, public/private/isolated tiers)
# and supplies the required flow log destination. Run `terraform init &&
# terraform validate` here to check it.

module "vpc" {
  source = "../../"

  region                   = "eu-west-2"
  flow_log_destination_arn = "arn:aws:s3:::example-log-archive-bucket"
}
