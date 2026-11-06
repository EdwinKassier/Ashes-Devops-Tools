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
  # Immutable numeric owner ID (gh api orgs/my-github-org --jq .id). The provider
  # condition is exactly assertion.repository_owner_id == "<id>".
  github_repository_owner_id = "12345678"

  # Bind the 'my-github-org/infra' repo (by its immutable numeric ID) to the
  # deploy service account. Only workflows in this repo can impersonate the SA.
  github_sa_bindings = [
    {
      repository            = "my-github-org/infra"
      repository_id         = "987654321" # gh api repos/my-github-org/infra --jq .id
      service_account_email = local.sa_email
    }
  ]

  # Only these exact refs may impersonate the SA (one attribute.repo_ref
  # binding per ref; wildcards are not supported).
  github_allowed_refs = [
    "refs/heads/main",
    "refs/heads/release",
  ]
}
