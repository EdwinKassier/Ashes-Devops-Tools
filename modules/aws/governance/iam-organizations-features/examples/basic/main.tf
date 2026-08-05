# Basic working example for the aws/iam-organizations-features module.
# Uses the module defaults (RootCredentialsManagement + RootSessions). Run
# `terraform init && terraform validate` here to check it.

module "iam_organizations_features" {
  source = "../../"
}
