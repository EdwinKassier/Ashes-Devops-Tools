output "pool_id" {
  description = "The Workload Identity Pool ID"
  value       = google_iam_workload_identity_pool.pool.workload_identity_pool_id
}

output "pool_name" {
  description = "The fully-qualified name of the Workload Identity Pool"
  value       = google_iam_workload_identity_pool.pool.name
}

output "github_provider_name" {
  description = "The fully-qualified name of the GitHub OIDC provider"
  value       = var.enable_github_provider ? google_iam_workload_identity_pool_provider.github[0].name : null
}

output "gitlab_provider_name" {
  description = "The fully-qualified name of the GitLab OIDC provider"
  value       = var.enable_gitlab_provider ? google_iam_workload_identity_pool_provider.gitlab[0].name : null
}

output "aws_provider_name" {
  description = "The fully-qualified name of the AWS provider"
  value       = var.enable_aws_provider ? google_iam_workload_identity_pool_provider.aws[0].name : null
}

# Helper output for GitHub Actions workflow configuration
output "github_workload_identity_provider" {
  description = "Provider string for use in GitHub Actions workflow (google-github-actions/auth)"
  value       = var.enable_github_provider ? "projects/${var.project_id}/locations/global/workloadIdentityPools/${var.pool_id}/providers/github" : null
}

# Principal set for attribute-based access
output "github_principal_set_prefix" {
  description = "Prefix for GitHub principal set (append /attribute.repository/owner/repo)"
  value       = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.pool.name}"
}
