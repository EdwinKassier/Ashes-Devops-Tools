# Google Cloud Workload Identity Federation Module
# Enables keyless authentication from external identity providers (GitHub Actions, AWS, Azure, etc.)

# Workload Identity Pool
resource "google_iam_workload_identity_pool" "pool" {
  project                   = var.project_id
  workload_identity_pool_id = var.pool_id
  display_name              = var.display_name
  description               = var.description
  disabled                  = var.disabled
}

# GitHub Actions OIDC Provider
resource "google_iam_workload_identity_pool_provider" "github" {
  count = var.enable_github_provider ? 1 : 0

  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub Actions"
  description                        = "OIDC provider for GitHub Actions"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.actor"            = "assertion.actor"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
  }

  # Optional: Restrict to specific repository owners
  attribute_condition = var.github_organization != null ? "assertion.repository_owner == '${var.github_organization}'" : null

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# GitLab CI OIDC Provider
resource "google_iam_workload_identity_pool_provider" "gitlab" {
  count = var.enable_gitlab_provider ? 1 : 0

  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "gitlab"
  display_name                       = "GitLab CI"
  description                        = "OIDC provider for GitLab CI/CD"

  attribute_mapping = {
    "google.subject"           = "assertion.sub"
    "attribute.project_id"     = "assertion.project_id"
    "attribute.project_path"   = "assertion.project_path"
    "attribute.namespace_path" = "assertion.namespace_path"
    "attribute.ref"            = "assertion.ref"
  }

  attribute_condition = var.gitlab_namespace != null ? "assertion.namespace_path.startsWith('${var.gitlab_namespace}')" : null

  oidc {
    issuer_uri = var.gitlab_url
  }
}

# AWS OIDC Provider (for cross-cloud authentication)
resource "google_iam_workload_identity_pool_provider" "aws" {
  count = var.enable_aws_provider ? 1 : 0

  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "aws-oidc"
  display_name                       = "AWS"
  description                        = "OIDC provider for AWS workloads"

  attribute_mapping = {
    "google.subject"    = "assertion.arn"
    "attribute.account" = "assertion.account"
    "attribute.role"    = "assertion.arn.extract('/assumed-role/{role}/')"
  }

  attribute_condition = var.aws_account_id != null ? "assertion.account == '${var.aws_account_id}'" : null

  aws {
    account_id = var.aws_account_id
  }
}

# Service Account IAM bindings for GitHub repos
resource "google_service_account_iam_member" "github_workload_identity" {
  for_each = { for binding in var.github_sa_bindings : "${binding.repository}-${binding.service_account_email}" => binding }

  service_account_id = "projects/${var.project_id}/serviceAccounts/${each.value.service_account_email}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.pool.name}/attribute.repository/${each.value.repository}"
}

# Service Account IAM bindings for GitLab projects
resource "google_service_account_iam_member" "gitlab_workload_identity" {
  for_each = { for binding in var.gitlab_sa_bindings : "${binding.project_path}-${binding.service_account_email}" => binding }

  service_account_id = "projects/${var.project_id}/serviceAccounts/${each.value.service_account_email}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.pool.name}/attribute.project_path/${each.value.project_path}"
}
