# Basic working example for the aws/iam-identity-center module.
# Uses the module defaults (AdministratorAccess + ReadOnly permission sets) and
# adds one GROUP assignment. Requires an already-enabled Identity Center
# instance in the org management account. Run `terraform init &&
# terraform validate` here to check it.

module "iam_identity_center" {
  source = "../../"

  assignments = {
    admins-management = {
      permission_set = "AdministratorAccess"
      principal_type = "GROUP"
      principal_id   = "00000000-0000-0000-0000-000000000000" # Identity Store group ID
      account_id     = "111111111111"
    }
  }
}
