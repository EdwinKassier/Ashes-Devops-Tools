# NOTE: the module source below is pinned to a release tag (?ref=v0.1.0, bumped
# by release-please through the x-release-please-version marker). Until the
# first release tag exists, `terraform init` fails on it. To try this example
# now, replace the source with the relative path "../../" (the module this
# example lives in). CI skips tag-pinned examples until that tag is cut.
#
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
  source = "git::https://github.com/EdwinKassier/Ashes-Devops-Tools.git//modules/aws/stages/security?ref=v0.1.0" # x-release-please-version

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

  # Every tuning input sits in one object (the aws section); unset keys take
  # the stage defaults. key_admin_arn / config_role_arn / aggregator_role_arn
  # omitted: each CMK is administered by its own account's tfc-apply role, and
  # the Config SLR + org aggregator role are created by the stage.
  aws = {
    log_archive_bucket_name     = "ashes-org-log-archive"
    meta_store_manager_role_arn = "arn:aws:iam::222222222222:role/AmazonSecurityLakeMetaStoreManager"
    break_glass_role_arn        = "arn:aws:iam::111111111111:role/break-glass"

    notification_subscribers = {
      secops = { protocol = "email", endpoint = "secops@example.com" }
    }
  }
}
