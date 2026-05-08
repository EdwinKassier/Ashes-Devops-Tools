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
