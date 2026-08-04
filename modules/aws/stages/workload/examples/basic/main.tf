# Basic working example for the aws-workload stage.
#
# The stage runs entirely in ONE workload account. The default provider covers
# the workload's home region; the us_east_1-aliased provider (SAME account) is
# threaded into the optional edge-security module. In a real deployment both
# providers assume the same workload-account role; here they use ambient
# credentials for a validate-only check. Run `terraform init && terraform
# validate` here.

provider "aws" {
  region = "eu-west-2"
  # assume_role { role_arn = "arn:aws:iam::222222222222:role/tfc-run-role" }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  # assume_role { role_arn = "arn:aws:iam::222222222222:role/tfc-run-role" }
}

module "aws_workload" {
  source = "../../"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  tgw_id                   = "tgw-000000000000abcd"
  flow_log_destination_arn = "arn:aws:s3:::ashes-org-log-archive"
  log_archive_bucket_name  = "ashes-org-log-archive"
  config_role_arn          = "arn:aws:iam::222222222222:role/config-recorder"
  kms_key_arn              = "arn:aws:kms:eu-west-2:222222222222:key/abcd-1234"
}
