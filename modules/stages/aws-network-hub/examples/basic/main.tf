# Basic working example for the aws-network-hub stage.
#
# The stage runs entirely in the NETWORK account with a SINGLE default provider.
# In a real deployment the provider assumes a role in the network account; here
# it uses ambient credentials for a validate-only check. Run
# `terraform init && terraform validate` here.

provider "aws" {
  region = "eu-west-2"
  # assume_role { role_arn = "arn:aws:iam::666666666666:role/tfc-run-role" }
}

module "aws_network_hub" {
  source = "../../"

  org_id  = "o-abc1234567"
  org_arn = "arn:aws:organizations::111111111111:organization/o-abc1234567"

  flow_log_destination_arn = "arn:aws:s3:::ashes-org-log-archive"
  log_bucket_name          = "ashes-org-log-archive"
}
