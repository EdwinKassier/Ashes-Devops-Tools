# Example: run the bootstrap stage (envs/gcp/bootstrap) to create the Terraform
# admin project, the per-stage plan/apply service accounts and the Terraform
# Cloud Workload Identity Federation pool.
#
# This is a one-time operation run with a human admin account. After bootstrap,
# Terraform Cloud applies every later stage with dynamic credentials.
#
# Prerequisites:
#   - A GCP organization with billing enabled
#   - An admin user with Organization Admin and Billing Account Admin roles
#   - A Terraform Cloud organization (replace my-tfc-org)

locals {
  org_id          = "123456789012"
  billing_account = "ABCDEF-123456-789012"
  admin_email     = "infra-admin@example.com"
}

module "bootstrap" {
  source = "../../"

  project_prefix  = "myorg-tf"
  org_id          = local.org_id
  billing_account = local.billing_account
  admin_email     = local.admin_email

  # Terraform Cloud dynamic credentials (enable_tfc_oidc defaults to true).
  tfc_organization = "my-tfc-org"
}
