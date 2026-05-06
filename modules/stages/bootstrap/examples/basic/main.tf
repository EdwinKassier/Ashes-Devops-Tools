# Example: run the bootstrap stage to create the Terraform admin project and
# configure Workload Identity Federation for GitHub Actions.
#
# This is a one-time operation run with a human admin account. After bootstrap,
# all subsequent changes are applied via GitHub Actions using the WIF credentials.
#
# Prerequisites:
#   - A GCP organization with billing enabled
#   - An admin user with Organization Admin and Billing Account Admin roles
#   - A GitHub repository where Terraform workflows will run

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

  github_org  = "my-github-org"
  github_repo = "infra"
}

output "terraform_sa_email" {
  description = "Service account email to configure in Terraform Cloud or GitHub Actions secrets"
  value       = module.bootstrap.terraform_admin_email
}

output "github_wif_provider" {
  description = "Workload Identity Provider name — set as WORKLOAD_IDENTITY_PROVIDER in GitHub Actions"
  value       = module.bootstrap.github_oidc_provider_name
}

output "admin_project_id" {
  description = "The seed project ID where Terraform state buckets and SA keys are managed"
  value       = module.bootstrap.admin_project_id
}
