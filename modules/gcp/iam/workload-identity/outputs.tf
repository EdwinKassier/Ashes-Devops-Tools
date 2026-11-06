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

output "tfc_provider_name" {
  description = "The fully-qualified name of the Terraform Cloud OIDC provider"
  value       = var.enable_tfc_provider ? google_iam_workload_identity_pool_provider.tfc[0].name : null
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

output "tfc_attribute_condition" {
  description = "The CEL attribute_condition applied to the Terraform Cloud provider (null when the TFC provider is disabled)."
  value       = var.enable_tfc_provider ? local.tfc_attribute_condition : null
}

output "tfc_binding_members" {
  description = "Map of \"<workspace_name>:<run_phase>\" to the principalSet member bound to roles/iam.workloadIdentityUser on the target SA."
  value       = { for k, b in google_service_account_iam_member.tfc_workload_identity : k => b.member }
}

output "github_attribute_condition" {
  description = "The CEL attribute_condition applied to the GitHub provider (null when the GitHub provider is disabled)."
  value       = var.enable_github_provider ? local.github_attribute_condition : null
}

output "github_binding_members" {
  description = "Map of GitHub binding key (\"<key>:<ref>\" when more than one github_allowed_refs entry is set) to the principalSet member bound to roles/iam.workloadIdentityUser."
  value       = { for k, b in google_service_account_iam_member.github_workload_identity : k => b.member }
}

output "github_binding_service_accounts" {
  description = "Map of GitHub binding key to the service account email granted roles/iam.workloadIdentityUser."
  value       = { for k, b in var.github_sa_bindings : (b.key != null ? b.key : "${b.repository}-${b.service_account_email}") => b.service_account_email }
}
