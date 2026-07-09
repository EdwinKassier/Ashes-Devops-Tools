# Basic working example for the aws/account module.
# Run `terraform init && terraform validate` here to check it.

module "account" {
  source = "../../"

  account_name = "log-archive"
  email        = "aws+logarchive@example.com"
  parent_ou_id = "ou-abc1-def2ghi3"
}
