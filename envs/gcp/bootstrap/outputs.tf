# Cross-root contract (Convention 4). Consumed by gcp-organization (and future
# gcp control-plane roots) via terraform_remote_state. Keep these keys stable
# across refactors — renaming one breaks the downstream root at plan.

output "admin_project_id" {
  description = "The admin (seed) project ID that hosts the Terraform admin SA and WIF pools."
  value       = module.bootstrap.admin_project_id
}

output "admin_project_number" {
  description = "The admin project number, used by WIF pool references and VPC-SC ingress policies."
  value       = module.bootstrap.admin_project_number
}

output "terraform_admin_email" {
  description = "Email of the Terraform admin service account the other roots impersonate."
  value       = module.bootstrap.terraform_admin_email
}

output "suffix" {
  description = "Random suffix used for globally-unique project IDs; shared with the projects stage for ID consistency."
  value       = module.bootstrap.suffix
}

output "github_oidc_pool_id" {
  description = "Workload Identity Pool ID for GitHub Actions OIDC."
  value       = module.bootstrap.github_oidc_pool_id
}

output "github_oidc_pool_name" {
  description = "Fully-qualified Workload Identity Pool name for GitHub Actions OIDC."
  value       = module.bootstrap.github_oidc_pool_name
}

output "github_oidc_provider_name" {
  description = "Fully-qualified WIF provider name for use in GitHub Actions (google-github-actions/auth)."
  value       = module.bootstrap.github_oidc_provider_name
}

output "tfc_oidc_pool_id" {
  description = "Workload Identity Pool ID for Terraform Cloud OIDC (null if TFC OIDC not configured)."
  value       = module.bootstrap.tfc_oidc_pool_id
}

output "tfc_oidc_pool_name" {
  description = "Fully-qualified Workload Identity Pool name for Terraform Cloud OIDC (null if not configured)."
  value       = module.bootstrap.tfc_oidc_pool_name
}

output "tfc_oidc_provider_name" {
  description = "Fully-qualified WIF provider name for Terraform Cloud OIDC (null if not configured)."
  value       = module.bootstrap.tfc_oidc_provider_name
}

output "resman_email" {
  description = "Email of the resource-management SA (populated when the privilege split is enabled)."
  value       = module.bootstrap.resman_email
}
