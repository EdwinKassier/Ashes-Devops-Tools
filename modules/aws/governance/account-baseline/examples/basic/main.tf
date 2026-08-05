# Basic working example for the aws/account-baseline module.
# Uses module defaults (single home Region, CIS password policy, S3 BPA).
# Run `terraform init && terraform validate` here to check it.

module "account_baseline" {
  source = "../../"

  aws_enabled_regions = ["eu-west-2"]
}
