# Basic working example for the aws/kms-key module.
# Creates a CMK for central log delivery with the default log-service grants.
# Run `terraform init && terraform validate` here to check it.

module "kms_key" {
  source = "../../"

  alias                 = "central-logs"
  org_id                = "o-abc123xyz0"
  management_account_id = "111122223333"
  key_admin_arn         = "arn:aws:iam::111122223333:role/KeyAdmin"
}
