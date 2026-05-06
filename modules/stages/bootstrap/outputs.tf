output "admin_project_id" {
  description = "Project ID of the admin project"
  value       = google_project.admin_project.project_id
}

output "admin_project_number" {
  description = "Project Number of the admin project"
  value       = google_project.admin_project.number
}

output "terraform_admin_email" {
  description = "Email of the Terraform Admin Service Account"
  value       = module.terraform_admin_sa.email
}

output "suffix" {
  description = "Random suffix used for uniqueness"
  value       = random_id.suffix.hex
}

output "github_oidc_pool_id" {
  description = "Workload Identity Pool ID for GitHub Actions OIDC"
  value       = module.gh_oidc.pool_id
}

output "github_oidc_pool_name" {
  description = "Fully-qualified Workload Identity Pool name for GitHub Actions OIDC"
  value       = module.gh_oidc.pool_name
}

output "github_oidc_provider_name" {
  description = "Fully-qualified Workload Identity Provider name for GitHub Actions"
  value       = module.gh_oidc.github_provider_name
}

output "tfc_oidc_pool_id" {
  description = "Workload Identity Pool ID for Terraform Cloud OIDC (null if TFC OIDC not enabled)"
  value       = length(module.tfc_oidc) > 0 ? module.tfc_oidc[0].pool_id : null
}

output "tfc_oidc_pool_name" {
  description = "Fully-qualified Workload Identity Pool name for Terraform Cloud OIDC (null if TFC OIDC not enabled)"
  value       = length(module.tfc_oidc) > 0 ? module.tfc_oidc[0].pool_name : null
}

output "tfc_oidc_provider_name" {
  description = "Fully-qualified Workload Identity Provider name for Terraform Cloud OIDC (null if TFC OIDC not enabled)"
  value       = length(module.tfc_oidc) > 0 ? module.tfc_oidc[0].tfc_provider_name : null
}
