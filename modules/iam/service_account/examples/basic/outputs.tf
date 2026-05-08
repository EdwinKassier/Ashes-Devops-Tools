output "service_account_email" {
  description = "Email address of the created service account"
  value       = module.api_service_sa.email
}

output "service_account_member" {
  description = "IAM member string (e.g. serviceAccount:...@project.iam.gserviceaccount.com)"
  value       = module.api_service_sa.member
}
