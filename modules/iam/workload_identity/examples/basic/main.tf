# Example: configure Workload Identity Federation so GitHub Actions workflows
# in a specific repo can impersonate a GCP service account without static keys.

locals {
  project_id = "my-platform-project"
  sa_email   = "github-deploy@my-platform-project.iam.gserviceaccount.com"
}

module "github_wif" {
  source = "../../"

  project_id   = local.project_id
  pool_id      = "github-pool"
  display_name = "GitHub Actions Pool"
  description  = "Allows GitHub Actions to authenticate to GCP via OIDC"

  enable_github_provider = true
  github_organization    = "my-github-org"

  # Bind the 'my-github-org/infra' repo to the deploy service account.
  # Only workflows in this repo can impersonate the SA.
  github_sa_bindings = [
    {
      repository            = "my-github-org/infra"
      service_account_email = local.sa_email
    }
  ]

  # Restrict to main branch and release branches.
  github_allowed_refs = [
    "refs/heads/main",
    "refs/heads/release/*",
  ]
}

output "workload_identity_provider" {
  description = "Full provider resource name for use in GitHub Actions 'workload_identity_provider' input"
  value       = module.github_wif.github_workload_identity_provider
}
