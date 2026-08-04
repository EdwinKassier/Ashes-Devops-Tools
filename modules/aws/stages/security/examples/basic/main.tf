# Basic working example for the aws-security stage.
#
# The stage runs across four accounts, so it declares four aliased providers.
# In a real deployment each provider assumes a role in its target account; here
# they use provider aliases against the same credentials for a validate-only
# check. Run `terraform init && terraform validate` here.

provider "aws" {
  alias  = "management"
  region = "eu-west-2"
  # assume_role { role_arn = "arn:aws:iam::111111111111:role/tfc-run-role" }
}

provider "aws" {
  alias  = "security_tooling"
  region = "eu-west-2"
  # assume_role { role_arn = "arn:aws:iam::222222222222:role/tfc-run-role" }
}

provider "aws" {
  alias  = "log_archive"
  region = "eu-west-2"
  # assume_role { role_arn = "arn:aws:iam::333333333333:role/tfc-run-role" }
}

provider "aws" {
  alias  = "forensics"
  region = "eu-west-2"
  # assume_role { role_arn = "arn:aws:iam::444444444444:role/tfc-run-role" }
}

module "aws_security" {
  source = "../../"

  providers = {
    aws.management       = aws.management
    aws.security_tooling = aws.security_tooling
    aws.log_archive      = aws.log_archive
    aws.forensics        = aws.forensics
  }

  org_id                      = "o-abc1234567"
  org_root_id                 = "r-abc1"
  management_account_id       = "111111111111"
  security_tooling_account_id = "222222222222"
  log_archive_account_id      = "333333333333"
  shared_services_account_id  = "555555555555"
  forensics_account_id        = "444444444444"

  log_archive_bucket_name     = "ashes-org-log-archive"
  key_admin_arn               = "arn:aws:iam::333333333333:role/kms-admin"
  config_role_arn             = "arn:aws:iam::222222222222:role/aws-config-role"
  aggregator_role_arn         = "arn:aws:iam::222222222222:role/aws-config-aggregator"
  meta_store_manager_role_arn = "arn:aws:iam::222222222222:role/AmazonSecurityLakeMetaStoreManager"
  break_glass_role_arn        = "arn:aws:iam::111111111111:role/break-glass"

  notification_subscribers = {
    secops = { protocol = "email", endpoint = "secops@example.com" }
  }
}
